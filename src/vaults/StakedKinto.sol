// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/**
 * @title StakedKinto
 * @notice A vault that allows users to stake tokens into a vault and earn rewards
 * @dev This contract implements a weighted timestamp staking mechanism for rewards distribution
 */
contract StakedKinto is Initializable, ERC4626Upgradeable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for ERC20Upgradeable;

    /* ============ Struct ============ */

    struct UserStake {
        uint256 amount;
        uint256 weightedTimestamp;
        uint256 untilPeriodId;
    }

    struct StakingPeriod {
        uint256 startTime;
        uint256 endTime;
        uint256 rewardRate;
        uint256 maxCapacity;
        ERC20Upgradeable rewardToken;
    }

    /* ============ Custom Errors ============ */

    error StakingPeriodEnded();
    error StakingPeriodNotEnded();
    error CannotWithdrawBeforeEndDate();
    error CannotRedeemBeforeEndDate();
    error RewardTransferFailed();
    error MaxCapacityReached();
    error EndDateMustBeInTheFuture();
    error InsufficientRewardTokenBalance();
    error NoPreviousPeriod();
    error NoPreviousStake();
    error AlreadyRolledOver();
    error RewardRateTooHigh();
    error DepositTooSmall();
    error CannotTransferAfterClaim();

    /* ============ Events ============ */
    event RewardsDistributed(address indexed user, uint256 amount);
    event StakeUpdated(address indexed user, uint256 amount, uint256 weightedTimestamp);
    event MaxCapacityUpdated(uint256 newMaxCapacity);
    event NewPeriodStarted(uint256 periodId, uint256 startTime, uint256 endTime);
    event Rollover(address indexed user, uint256 amount, uint256 weightedTimestamp);

    /* ============ Constants ============ */
    uint256 private constant MAX_REWARD_RATE = 50; // 50% APY cap

    /* ============ State ============ */

    ERC20Upgradeable private __rewardToken__deprecated;
    StakingPeriod[] private stakingPeriods;
    uint256 public currentPeriodId;
    mapping(uint256 => mapping(address => bool)) public hasClaimedRewards;

    mapping(uint256 => mapping(address => UserStake)) private _periodUserStakes;
    mapping(address => bool) public hasClaimedICOBonus;
    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // Save Space on new deployments
    function initialize(
        IERC20MetadataUpgradeable _stakingToken,
        ERC20Upgradeable _rewardToken,
        uint256 _rewardRate,
        uint256 _endDate,
        string memory _name,
        string memory _symbol,
        uint256 _maxCapacity
    ) external initializer {
        __ERC4626_init(_stakingToken);
        __ERC20_init_unchained(_name, _symbol);
        __Ownable_init_unchained();
        __UUPSUpgradeable_init();

        __rewardToken__deprecated = _rewardToken;

        _startNewPeriod(_endDate, _rewardRate, _maxCapacity, address(_rewardToken));

        emit MaxCapacityUpdated(_maxCapacity);
    }

    /* ============ Admin Functions ============ */

    /**
     * @notice Sets a new maximum capacity for the vault
     * @param _newMaxCapacity The new maximum capacity
     */
    function setMaxCapacity(uint256 _newMaxCapacity) external onlyOwner {
        stakingPeriods[currentPeriodId].maxCapacity = _newMaxCapacity;
        emit MaxCapacityUpdated(_newMaxCapacity);
    }

    /**
     * @notice Sets a new end time for the current period
     * @param _endTime The new end time
     */
    function setEndTime(uint256 _endTime) external onlyOwner {
        stakingPeriods[currentPeriodId].endTime = _endTime;
    }

    /**
     * @notice Starts a new staking period
     * @param _endDate The end date of the new period
     * @param _rewardRate The reward rate for the new period
     * @param _maxCapacity The maximum capacity for the new period
     * @param _rewardToken The reward token for the new period
     */
    function startNewPeriod(uint256 _endDate, uint256 _rewardRate, uint256 _maxCapacity, address _rewardToken)
        external
        onlyOwner
    {
        _startNewPeriod(_endDate, _rewardRate, _maxCapacity, _rewardToken);
    }

    // Required by UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* ============ User State Functions ============ */

    // function burnCurrentPeriodStake(address account, uint256 shares) public onlyOwner {
    //     require(shares > 0, "ZeroShares");

    //     // How many underlying tokens those shares represent *right now*
    //     uint256 assets = previewRedeem(shares);

    //     // ── 1. Adjust stake bookkeeping ───────────────────────────────────────────
    //     UserStake storage st = _periodUserStakes[currentPeriodId][account];
    //     if (assets > st.amount) revert("BurnExceedsStake");
    //     st.amount -= assets;

    //     if (st.amount == 0) {
    //         delete _periodUserStakes[currentPeriodId][account];
    //         delete hasClaimedRewards[currentPeriodId][account]; // gas cleanup
    //     }

    //     // ── 2. Burn the ERC20 shares (triggers _afterTokenTransfer, which ignores burns)
    //     _burn(account, shares);
    // }

    // function batchBurnCurrentPeriodStake(address[] calldata accounts, uint256[] calldata shares) external onlyOwner {
    //     for (uint256 i = 0; i < accounts.length; i++) {
    //         burnCurrentPeriodStake(accounts[i], shares[i]);
    //     }
    // }

    // function batchMintCurrentPeriodStake(address[] calldata accounts, uint256[] calldata shares) external onlyOwner {
    //     for (uint256 i = 0; i < accounts.length; i++) {
    //         _innerDeposit(shares[i], accounts[i], 1);
    //         // Need to mint sK without taking K
    //         _mint(accounts[i], shares[i]);
    //     }
    // }

    function depositWithBonus(uint256 assets, address receiver, uint256 untilPeriodId) public returns (uint256) {
        uint256 assetsWithBonus = _innerDeposit(assets, receiver, untilPeriodId);
        return super.deposit(assetsWithBonus, receiver);
    }

    // Override deposit function to implement weighted timestamp logic and check capacity
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        _innerDeposit(assets, receiver, currentPeriodId);

        // Call parent deposit function to handle the actual token transfer and share minting
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        _innerDeposit(convertToAssets(shares), receiver, currentPeriodId);
        return super.mint(shares, receiver);
    }

    // Override withdraw function to prevent withdrawals before end date
    function withdraw(uint256 assets, address receiver, address owner) public virtual override returns (uint256) {
        _handleRewardsAndReset(owner, receiver);

        // Call parent withdraw function to handle the actual token transfer and share burning
        return super.withdraw(assets, receiver, owner);
    }

    // Override redeem function to prevent redemptions before end date
    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256) {
        _handleRewardsAndReset(owner, receiver);

        // Call parent redeem function to handle the actual token transfer and share burning
        return super.redeem(shares, receiver, owner);
    }

    function icoTokensAction(uint256 icoShares, bool isWithdraw, uint256 untilPeriodId) external {
        uint256 stakedBalance = balanceOf(msg.sender);
        if (icoShares > stakedBalance || hasClaimedICOBonus[msg.sender]) {
            revert DepositTooSmall();
        }
        if (isWithdraw) {
            // Just redeem the shares. Skip max redeem logic
            uint256 assets = previewRedeem(icoShares);
            _withdraw(msg.sender, msg.sender, msg.sender, assets, icoShares);
        } else {
            // Transform into normal stake
            _innerDeposit(icoShares, msg.sender, untilPeriodId);
        }
        // USDC Bonus
        uint256 usdcBonus = (isWithdraw ? icoShares / 4 : icoShares / 2) / 1e12;
        hasClaimedICOBonus[msg.sender] = true;
        __rewardToken__deprecated.safeTransfer(msg.sender, usdcBonus);
    }

    /* ============ View Functions ============ */

    /**
     * @notice Returns the maximum amount of assets that can be deposited
     * param receiver The address that would receive the assets
     * @return The maximum amount of assets that can be deposited
     */
    function maxDeposit(address /* receiver */ ) public view override returns (uint256) {
        return _getRemainingCapacity();
    }

    /**
     * @notice Returns the maximum amount of shares that can be minted
     * param _receiver The address that would receive the shares (unused)
     * @return The maximum amount of shares that can be minted
     */
    function maxMint(address /* _receiver */ ) public view override returns (uint256) {
        return _convertToShares(_getRemainingCapacity(), MathUpgradeable.Rounding.Down);
    }

    function maxRedeem(address user) public view override returns (uint256) {
        uint256 userStake = _checkWithdrawAllowed(user);
        return _convertToShares(userStake, MathUpgradeable.Rounding.Down);
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return _checkWithdrawAllowed(owner);
    }

    /**
     * @notice Calculate rewards for a user in a specific period
     * @param user The address of the user
     * @param periodId The ID of the period
     * @return The amount of rewards for the user in the period
     */
    function calculateRewards(address user, uint256 periodId) public view returns (uint256) {
        StakingPeriod memory period = stakingPeriods[periodId];
        UserStake memory userStake = _periodUserStakes[periodId][user];

        if (userStake.amount == 0 || hasClaimedRewards[periodId][user]) return 0;

        uint256 stakingDuration = period.endTime - userStake.weightedTimestamp;

        address rewardToken =
            address(period.rewardToken) != address(0) ? address(period.rewardToken) : address(__rewardToken__deprecated);

        // Simplify calculation
        return (userStake.amount * period.rewardRate * stakingDuration) / (365 days) / 15
            / (10 ** (18 - IERC20MetadataUpgradeable(rewardToken).decimals())) * 2;
    }

    /**
     * @notice Get user's staking information
     * @param user The address of the user
     * @param periodId The ID of the period
     * @return amount The amount of staked tokens
     * @return weightedTimestamp The weighted timestamp
     * @return pendingRewards The pending rewards
     */
    function getUserStakeInfo(address user, uint256 periodId)
        external
        view
        returns (uint256 amount, uint256 weightedTimestamp, uint256 pendingRewards)
    {
        UserStake storage userStake = _periodUserStakes[periodId][user];
        return (userStake.amount, userStake.weightedTimestamp, calculateRewards(user, periodId));
    }

    function getUserStakeUntilPeriodId(address user, uint256 periodId) external view returns (uint256) {
        return _periodUserStakes[periodId][user].untilPeriodId;
    }

    /**
     * @notice Returns the information for a specific staking period
     * @param periodId The ID of the period
     * @return startTime The start time of the period
     * @return endTime The end time of the period
     * @return rewardRate The reward rate for the period
     * @return maxCapacity The maximum capacity for the period
     * @return rewardToken The reward token for the period
     */
    function getPeriodInfo(uint256 periodId)
        external
        view
        returns (uint256 startTime, uint256 endTime, uint256 rewardRate, uint256 maxCapacity, address rewardToken)
    {
        StakingPeriod memory period = stakingPeriods[periodId];
        return (period.startTime, period.endTime, period.rewardRate, period.maxCapacity, address(period.rewardToken));
    }

    /* ============ Private Functions ============ */

    /// @dev Hook called by OpenZeppelin ERC20 after *any* share movement:
    /// mint, burn, transfer, or transferFrom.
    function _afterTokenTransfer(address from, address to, uint256 /* amount */ ) internal virtual override {
        // Ignore mint, burn, or self-transfer.
        if (from == address(0) || to == address(0) || from == to) return;

        for (uint256 i; i <= currentPeriodId; ++i) {
            UserStake storage sFrom = _periodUserStakes[i][from];
            if (sFrom.amount == 0) continue;

            // ✅ protect receiver’s un-claimed rewards
            if (hasClaimedRewards[i][from] && !hasClaimedRewards[i][to]) {
                revert CannotTransferAfterClaim();
            }

            UserStake storage sTo = _periodUserStakes[i][to];

            if (sTo.amount == 0) {
                // Simple move.
                _periodUserStakes[i][to] = sFrom;
            } else {
                uint256 total = sTo.amount + sFrom.amount;
                sTo.weightedTimestamp =
                    (sTo.weightedTimestamp * sTo.amount + sFrom.weightedTimestamp * sFrom.amount) / total;
                sTo.amount = total;
                if (sFrom.untilPeriodId > sTo.untilPeriodId) {
                    sTo.untilPeriodId = sFrom.untilPeriodId;
                }
            }

            // Merge reward-claim bitmap.
            hasClaimedRewards[i][to] = hasClaimedRewards[i][to] || hasClaimedRewards[i][from];

            // Clean up sender.
            delete _periodUserStakes[i][from];
            delete hasClaimedRewards[i][from];
        }
    }

    /* ============ Internal Functions ============ */

    function _handleRewardsAndReset(address user, address receiver) private {
        uint256 withdrawableAmount = _checkWithdrawAllowed(user);
        if (withdrawableAmount == 0) {
            revert CannotWithdrawBeforeEndDate();
        }
        // Previous periods (use a more efficient loop)
        for (uint256 i = 0; i < currentPeriodId; i++) {
            if (!hasClaimedRewards[i][user] && _periodUserStakes[i][user].amount > 0) {
                ERC20Upgradeable rewardToken = address(stakingPeriods[i].rewardToken) != address(0)
                    ? stakingPeriods[i].rewardToken
                    : __rewardToken__deprecated;
                uint256 rewardsPeriod = calculateRewards(user, i);

                if (rewardToken.balanceOf(address(this)) < rewardsPeriod) {
                    revert InsufficientRewardTokenBalance();
                }
                hasClaimedRewards[i][user] = true;
                rewardToken.safeTransfer(receiver, rewardsPeriod);
                emit RewardsDistributed(user, rewardsPeriod);
            }
        }
    }

    // Helper function to start a new staking period

    function _startNewPeriod(uint256 _endDate, uint256 _rewardRate, uint256 _maxCapacity, address _rewardToken)
        private
    {
        if (_endDate <= block.timestamp) revert EndDateMustBeInTheFuture();
        if (_rewardRate > MAX_REWARD_RATE) revert RewardRateTooHigh();

        stakingPeriods.push(
            StakingPeriod({
                startTime: uint64(block.timestamp),
                endTime: uint64(_endDate),
                rewardRate: uint32(_rewardRate),
                maxCapacity: uint96(_maxCapacity),
                rewardToken: ERC20Upgradeable(_rewardToken)
            })
        );

        currentPeriodId = stakingPeriods.length - 1;
        emit NewPeriodStarted(currentPeriodId, block.timestamp, _endDate);
    }

    function _innerDeposit(uint256 assets, address receiver, uint256 untilPeriodId) private returns (uint256) {
        StakingPeriod memory currentPeriod = stakingPeriods[currentPeriodId];
        if (untilPeriodId < currentPeriodId || block.timestamp >= currentPeriod.endTime) revert StakingPeriodEnded();

        // Check if deposit would exceed max capacity
        if (totalAssets() + assets > currentPeriod.maxCapacity) revert MaxCapacityReached();
        if (assets == 0) revert DepositTooSmall();
        // Get current stake info
        UserStake storage userStake = _periodUserStakes[currentPeriodId][receiver];

        // Calculate new weighted timestamp
        if (userStake.amount > 0) {
            // Use moving average formula to update weighted timestamp
            userStake.weightedTimestamp = (
                (userStake.amount * userStake.weightedTimestamp) + (assets * block.timestamp)
            ) / (userStake.amount + assets);
        } else {
            // First deposit sets timestamp directly
            userStake.weightedTimestamp = block.timestamp;
        }

        if (untilPeriodId > userStake.untilPeriodId) {
            userStake.untilPeriodId = untilPeriodId;
        }
        // Longer bonus
        uint256 bonus = 0;
        if (untilPeriodId > currentPeriodId) {
            uint256 diff = untilPeriodId - currentPeriodId;
            bonus = (diff * (diff + 7) * 1e16) / 2;
            bonus = (bonus * assets) / 1e18;
        }

        // Update stake amount
        userStake.amount += assets + bonus;

        emit StakeUpdated(receiver, userStake.amount, userStake.weightedTimestamp);

        return assets;
    }

    function _getRemainingCapacity() private view returns (uint256) {
        StakingPeriod memory currentPeriod = stakingPeriods[currentPeriodId];
        if (block.timestamp >= currentPeriod.endTime) {
            return 0;
        }

        uint256 currentAssets = totalAssets();
        if (currentAssets >= currentPeriod.maxCapacity) {
            return 0;
        }

        return currentPeriod.maxCapacity - currentAssets;
    }

    function _checkWithdrawAllowed(address user) private view returns (uint256) {
        StakingPeriod memory currentPeriod = stakingPeriods[currentPeriodId];

        uint256 userStake = _periodUserStakes[currentPeriodId][user].amount;

        // User staked in the current period and the period has not ended
        if (userStake > 0 && block.timestamp < currentPeriod.endTime) {
            return 0; // Cannot withdraw before end date
        }

        uint256 currentAssets = totalAssets();
        if (currentAssets == 0) {
            return 0;
        }

        if (userStake == 0 && currentPeriodId > 0) {
            // No stake in the current period
            // Previous periods (use a more efficient loop)
            for (uint256 i = 0; i < currentPeriodId; i++) {
                uint256 amount = _periodUserStakes[i][user].amount;
                if (amount > 0 && _periodUserStakes[i][user].untilPeriodId <= currentPeriodId) {
                    userStake = _periodUserStakes[i][user].amount;
                }
            }
        }

        return userStake;
    }
}

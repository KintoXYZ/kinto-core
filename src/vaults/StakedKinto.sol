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
    }

    struct StakingPeriod {
        uint256 startTime;
        uint256 endTime;
        uint256 rewardRate;
        uint256 maxCapacity;
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

    /* ============ Events ============ */
    event RewardsDistributed(address indexed user, uint256 amount);
    event StakeUpdated(address indexed user, uint256 amount, uint256 weightedTimestamp);
    event MaxCapacityUpdated(uint256 newMaxCapacity);
    event NewPeriodStarted(uint256 periodId, uint256 startTime, uint256 endTime);
    event Rollover(address indexed user, uint256 amount, uint256 weightedTimestamp);

    /* ============ Constants ============ */
    uint256 private constant MAX_REWARD_RATE = 50; // 50% APY cap

    /* ============ State ============ */

    ERC20Upgradeable private rewardToken;
    StakingPeriod[] private stakingPeriods;
    uint256 public currentPeriodId;
    mapping(uint256 => mapping(address => bool)) public hasClaimedRewards;

    mapping(uint256 => mapping(address => UserStake)) private _periodUserStakes;
    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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

        rewardToken = _rewardToken;

        _startNewPeriod(_endDate, _rewardRate, _maxCapacity);

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
     * @notice Starts a new staking period
     * @param _endDate The end date of the new period
     * @param _rewardRate The reward rate for the new period
     * @param _maxCapacity The maximum capacity for the new period
     */
    function startNewPeriod(uint256 _endDate, uint256 _rewardRate, uint256 _maxCapacity) external onlyOwner {
        _startNewPeriod(_endDate, _rewardRate, _maxCapacity);
    }

    // Required by UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* ============ User State Functions ============ */

    function rollover() external {
        if (currentPeriodId == 0) revert NoPreviousPeriod();
        StakingPeriod memory currentPeriod = stakingPeriods[currentPeriodId];
        // Grab data from last period
        UserStake memory lastPeriodUserStake = _periodUserStakes[currentPeriodId - 1][msg.sender];
        if (lastPeriodUserStake.amount == 0) revert NoPreviousStake();
        if (_periodUserStakes[currentPeriodId][msg.sender].amount > 0) revert AlreadyRolledOver();
        _periodUserStakes[currentPeriodId][msg.sender] =
            UserStake({amount: lastPeriodUserStake.amount, weightedTimestamp: currentPeriod.startTime});
        emit Rollover(msg.sender, lastPeriodUserStake.amount, currentPeriod.startTime);
    }

    // Override deposit function to implement weighted timestamp logic and check capacity
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        _innerDeposit(assets, receiver);

        // Call parent deposit function to handle the actual token transfer and share minting
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        _innerDeposit(convertToAssets(shares), receiver);
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

        // Simplify calculation
        return (userStake.amount * period.rewardRate * stakingDuration) / (365 days)
            / (10 ** (18 - rewardToken.decimals())) * 2;
    }

    /**
     * @notice Get user's staking information
     * @param user The address of the user
     * @return amount The amount of staked tokens
     * @return weightedTimestamp The weighted timestamp
     * @return pendingRewards The pending rewards
     */
    function getUserStakeInfo(address user)
        external
        view
        returns (uint256 amount, uint256 weightedTimestamp, uint256 pendingRewards)
    {
        UserStake storage userStake = _periodUserStakes[currentPeriodId][user];
        return (userStake.amount, userStake.weightedTimestamp, calculateRewards(user, currentPeriodId));
    }

    /**
     * @notice Returns true if the user needs to rollover
     * @param user The address of the user
     * @return True if the user needs to rollover, false otherwise
     */
    function needsRollover(address user) external view returns (bool) {
        return _periodUserStakes[currentPeriodId - 1][user].amount > 0
            && _periodUserStakes[currentPeriodId][user].amount == 0;
    }

    /**
     * @notice Returns the information for a specific staking period
     * @param periodId The ID of the period
     * @return startTime The start time of the period
     * @return endTime The end time of the period
     * @return rewardRate The reward rate for the period
     * @return maxCapacity The maximum capacity for the period
     */
    function getPeriodInfo(uint256 periodId)
        external
        view
        returns (uint256 startTime, uint256 endTime, uint256 rewardRate, uint256 maxCapacity)
    {
        StakingPeriod memory period = stakingPeriods[periodId];
        return (period.startTime, period.endTime, period.rewardRate, period.maxCapacity);
    }

    /* ============ Internal Functions ============ */

    function _handleRewardsAndReset(address user, address receiver) private {
        uint256 endDate = stakingPeriods[currentPeriodId].endTime;
        if (block.timestamp < endDate) revert CannotWithdrawBeforeEndDate();
        // Combine reward calculations
        uint256 totalRewards = 0;

        // Previous periods (use a more efficient loop)
        for (uint256 i = 0; i <= currentPeriodId; ++i) {
            if (!hasClaimedRewards[i][user]) {
                totalRewards += calculateRewards(user, i);
                hasClaimedRewards[i][user] = true;
            }
        }

        // Single transfer instead of multiple
        if (totalRewards > 0) {
            if (rewardToken.balanceOf(address(this)) < totalRewards) {
                revert InsufficientRewardTokenBalance();
            }
            rewardToken.safeTransfer(receiver, totalRewards);
            emit RewardsDistributed(user, totalRewards);
        }
    }

    // Helper function to start a new staking period
    function _startNewPeriod(uint256 _endDate, uint256 _rewardRate, uint256 _maxCapacity) private {
        if (_endDate <= block.timestamp) revert EndDateMustBeInTheFuture();
        if (_rewardRate > MAX_REWARD_RATE) revert RewardRateTooHigh();

        stakingPeriods.push(
            StakingPeriod({
                startTime: uint64(block.timestamp),
                endTime: uint64(_endDate),
                rewardRate: uint32(_rewardRate),
                maxCapacity: uint96(_maxCapacity)
            })
        );

        currentPeriodId = stakingPeriods.length - 1;
        emit NewPeriodStarted(currentPeriodId, block.timestamp, _endDate);
    }

    function _innerDeposit(uint256 assets, address receiver) private {
        StakingPeriod memory currentPeriod = stakingPeriods[currentPeriodId];
        if (block.timestamp >= currentPeriod.endTime) revert StakingPeriodEnded();

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

        // Update stake amount
        userStake.amount += assets;

        emit StakeUpdated(receiver, userStake.amount, userStake.weightedTimestamp);
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
        if (block.timestamp < currentPeriod.endTime) {
            return 0; // Cannot withdraw before end date
        }

        uint256 currentAssets = totalAssets();
        if (currentAssets == 0) {
            return 0;
        }

        uint256 userStake = _periodUserStakes[currentPeriodId][user].amount;
        if (userStake == 0) {
            return 0;
        }

        return userStake;
    }
}

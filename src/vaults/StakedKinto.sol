// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol';
import {ERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import {
    IERC20Upgradeable,
    IERC20MetadataUpgradeable
} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {SafeMathUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol';
import {SafeERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import {MathUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol';

/**
 * @title StakedKinto
 * @notice A vault that allows users to stake tokens into a vault and earn rewards
 * @dev This contract implements a weighted timestamp staking mechanism for rewards distribution
 */
contract StakedKinto is Initializable, ERC4626Upgradeable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ============ Struct ============ */

    struct UserStake {
        uint256 amount;
        uint256 weightedTimestamp;
        bool hasClaimedRewards;
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

    /* ============ Events ============ */
    event RewardsDistributed(address indexed user, uint256 amount);
    event StakeUpdated(address indexed user, uint256 amount, uint256 weightedTimestamp);
    event MaxCapacityUpdated(uint256 newMaxCapacity);
    event NewPeriodStarted(uint256 periodId, uint256 startTime, uint256 endTime);
    event Rollover(address indexed user, uint256 amount, uint256 weightedTimestamp);

    /* ============ State ============ */
    
    IERC20Upgradeable public rewardToken;
    StakingPeriod[] public stakingPeriods;
    uint256 public currentPeriodId;
    mapping(uint256 => mapping(address => UserStake)) public periodUserStakes;
    mapping(uint256 => mapping(address => bool)) public hasClaimedRewards;

    /* ============ Constructor ============ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IERC20MetadataUpgradeable _stakingToken,
        IERC20Upgradeable _rewardToken,
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
    function startNewPeriod(
        uint256 _endDate,
        uint256 _rewardRate,
        uint256 _maxCapacity
    ) external onlyOwner {
        _startNewPeriod(_endDate, _rewardRate, _maxCapacity);
    }

    // Required by UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* ============ User State Functions ============ */

    function rollover() external {
        if (currentPeriodId == 0) revert NoPreviousPeriod();
        StakingPeriod memory currentPeriod = stakingPeriods[currentPeriodId];
        // Grab data from last period
        UserStake memory lastPeriodUserStake = periodUserStakes[currentPeriodId - 1][msg.sender];
        if (lastPeriodUserStake.amount == 0) revert NoPreviousStake();
        if (periodUserStakes[currentPeriodId][msg.sender].amount > 0) revert AlreadyRolledOver();
        periodUserStakes[currentPeriodId][msg.sender] = UserStake({
            amount: lastPeriodUserStake.amount,
            weightedTimestamp: currentPeriod.startTime,
            hasClaimedRewards: false
        });
        emit Rollover(msg.sender, lastPeriodUserStake.amount, currentPeriod.startTime);
    }

    // Override deposit function to implement weighted timestamp logic and check capacity
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        StakingPeriod memory currentPeriod = stakingPeriods[currentPeriodId];
        if (block.timestamp >= currentPeriod.endTime) revert StakingPeriodEnded();

        // Check if deposit would exceed max capacity
        if (totalAssets() + assets > currentPeriod.maxCapacity) revert MaxCapacityReached();

        // Get current stake info
        UserStake storage userStake = periodUserStakes[currentPeriodId][receiver];

        // Calculate new weighted timestamp
        if (userStake.amount > 0) {
            // Calculate weighted timestamp: (oldAmount * oldTimestamp + newAmount * currentTimestamp) / totalAmount
            uint256 totalAmount = userStake.amount.add(assets);
            uint256 weightedTimestamp =
                userStake.amount.mul(userStake.weightedTimestamp).add(assets.mul(block.timestamp)).div(totalAmount);

            userStake.weightedTimestamp = weightedTimestamp;
            userStake.amount = totalAmount;
        } else {
            // First time staking
            userStake.amount = assets;
            userStake.weightedTimestamp = block.timestamp;
        }

        emit StakeUpdated(receiver, userStake.amount, userStake.weightedTimestamp);

        // Call parent deposit function to handle the actual token transfer and share minting
        return super.deposit(assets, receiver);
    }

    // Override withdraw function to prevent withdrawals before end date
    function withdraw(uint256 assets, address receiver, address owner) public virtual override returns (uint256) {
        uint256 endDate = stakingPeriods[currentPeriodId].endTime;
        if (block.timestamp < endDate) revert CannotWithdrawBeforeEndDate();

        _handleRewardsAndReset(owner, receiver);

        // Call parent withdraw function to handle the actual token transfer and share burning
        return super.withdraw(assets, receiver, owner);
    }

    // Override redeem function to prevent redemptions before end date
    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256) {
        uint256 endDate = stakingPeriods[currentPeriodId].endTime;
        if (block.timestamp < endDate) revert CannotRedeemBeforeEndDate();

        _handleRewardsAndReset(owner, receiver);

        // Call parent redeem function to handle the actual token transfer and share burning
        return super.redeem(shares, receiver, owner);
    }

    /* ============ View Functions ============ */

    /**
     * @notice Returns the maximum amount of assets that can be deposited
     * @param receiver The address that would receive the assets
     * @return The maximum amount of assets that can be deposited
     */
    function maxDeposit(address receiver) public view override returns (uint256) {
        StakingPeriod memory currentPeriod = stakingPeriods[currentPeriodId];
        if (block.timestamp >= currentPeriod.endTime) {
            return 0;
        }

        uint256 currentAssets = totalAssets();
        if (currentAssets >= currentPeriod.maxCapacity) {
            return 0;
        }

        uint256 remainingCapacity = currentPeriod.maxCapacity - currentAssets;
        return remainingCapacity < super.maxDeposit(receiver) ? remainingCapacity : super.maxDeposit(receiver);
    }

    /**
     * @notice Returns the maximum amount of shares that can be minted
     * param _receiver The address that would receive the shares (unused)
     * @return The maximum amount of shares that can be minted
     */
    function maxMint(address /* _receiver */ ) public view override returns (uint256) {
        StakingPeriod memory currentPeriod = stakingPeriods[currentPeriodId];
        if (block.timestamp >= currentPeriod.endTime) {
            return 0;
        }

        uint256 currentAssets = totalAssets();
        if (currentAssets >= currentPeriod.maxCapacity) {
            return 0;
        }

        uint256 remainingCapacity = currentPeriod.maxCapacity - currentAssets;
        return _convertToShares(remainingCapacity, MathUpgradeable.Rounding.Down);
    }

    /**
     * @notice Calculate rewards for a user in a specific period
     * @param user The address of the user
     * @param periodId The ID of the period
     * @return The amount of rewards for the user in the period
     */
    function calculateRewards(address user, uint256 periodId) public view returns (uint256) {
        StakingPeriod memory currentPeriod = stakingPeriods[periodId];
        UserStake storage userStake = periodUserStakes[periodId][user];

        if (userStake.amount == 0) {
            return 0;
        }

        // Calculate staking duration (capped at end date)
        uint256 stakingEndTime = block.timestamp < currentPeriod.endTime ? block.timestamp : currentPeriod.endTime;
        uint256 stakingDuration = stakingEndTime.sub(userStake.weightedTimestamp);

        // Calculate rewards: amount * rate * duration / (365 days * 100)
        // This assumes rewardRate is in percentage per year
        return userStake.amount.mul(currentPeriod.rewardRate).mul(stakingDuration).div(365 days).div(100);
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
        UserStake storage userStake = periodUserStakes[currentPeriodId][user];
        return (userStake.amount, userStake.weightedTimestamp, calculateRewards(user, currentPeriodId));
    }

    /**
     * @notice Returns true if the user needs to rollover
     * @param user The address of the user
     * @return True if the user needs to rollover, false otherwise
     */
    function needsRollover(address user) public view returns (bool) {
        return periodUserStakes[currentPeriodId - 1][user].amount > 0 &&
            periodUserStakes[currentPeriodId][user].amount == 0;
    }

    /**
     * @notice Returns the information for a specific staking period
     * @param periodId The ID of the period
     * @return startTime The start time of the period
     * @return endTime The end time of the period
     * @return rewardRate The reward rate for the period
     * @return maxCapacity The maximum capacity for the period
     */
    function getPeriodInfo(uint256 periodId) public view returns (
        uint256 startTime,
        uint256 endTime,
        uint256 rewardRate,
        uint256 maxCapacity
    ) {
        StakingPeriod memory period = stakingPeriods[periodId];
        return (period.startTime, period.endTime, period.rewardRate, period.maxCapacity);
    }

    /* ============ Internal Functions ============ */

    // Helper function to handle rewards and reset user stake data
    function _handleRewardsAndReset(address user, address receiver) internal {
        // Calculate and transfer rewards
        uint256 rewards = 0;

        // Claim previous periods if any
        for (uint256 i = 0; i <= currentPeriodId; i++) {
            if (!hasClaimedRewards[i][user]) {
                uint256 rewardsPeriod = calculateRewards(user, i);
                if (rewardsPeriod > 0) {
                    rewards = rewards.add(rewardsPeriod);
                    hasClaimedRewards[i][user] = true;
                }
            }
        }

        if (rewards > 0) {
            if (rewardToken.balanceOf(address(this)) < rewards) revert InsufficientRewardTokenBalance();
            rewardToken.safeTransfer(receiver, rewards);
            emit RewardsDistributed(user, rewards);
            hasClaimedRewards[currentPeriodId][user] = true;
        }
    }

    // Helper function to start a new staking period
    function _startNewPeriod(uint256 _endDate, uint256 _rewardRate, uint256 _maxCapacity) internal {
        // If there's a previous period, check it's ended
        if (stakingPeriods.length > 0) {
            // Change to custom error
            if (block.timestamp < stakingPeriods[currentPeriodId].endTime) revert StakingPeriodNotEnded();
        }
        // Ensure new end date is in the future
        if (_endDate <= block.timestamp) revert EndDateMustBeInTheFuture();

        stakingPeriods.push(StakingPeriod({
            startTime: block.timestamp,
            endTime: _endDate,
            rewardRate: _rewardRate,
            maxCapacity: _maxCapacity
        }));

        currentPeriodId = stakingPeriods.length - 1;

        emit NewPeriodStarted(currentPeriodId, block.timestamp, _endDate);
    }
}

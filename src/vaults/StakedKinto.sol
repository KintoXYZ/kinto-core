// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol';
import {ERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import {IERC20Upgradeable, IERC20MetadataUpgradeable} from
    '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol';
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
    }

    /* ============ Custom Errors ============ */
    error StakingPeriodEnded();
    error CannotWithdrawBeforeEndDate();
    error CannotRedeemBeforeEndDate();
    error RewardTransferFailed();
    error MaxCapacityReached();

    /* ============ Events ============ */
    event RewardsDistributed(address indexed user, uint256 amount);
    event StakeUpdated(address indexed user, uint256 amount, uint256 weightedTimestamp);
    event MaxCapacityUpdated(uint256 newMaxCapacity);

    /* ============ State ============ */
    IERC20Upgradeable public rewardToken;
    mapping(address => UserStake) public userStakes;
    uint256 public rewardRate;
    uint256 public endDate;
    uint256 public maxCapacity; // Maximum amount of assets the vault can hold

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
        rewardRate = _rewardRate;
        endDate = _endDate;
        maxCapacity = _maxCapacity;
        
        emit MaxCapacityUpdated(_maxCapacity);
    }

    /* ============ Admin Functions ============ */
    
    /**
     * @notice Sets a new maximum capacity for the vault
     * @param _newMaxCapacity The new maximum capacity
     */
    function setMaxCapacity(uint256 _newMaxCapacity) external onlyOwner {
        maxCapacity = _newMaxCapacity;
        emit MaxCapacityUpdated(_newMaxCapacity);
    }

    // Required by UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /* ============ User State Functions ============ */
    
    // Override deposit function to implement weighted timestamp logic and check capacity
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        if (block.timestamp >= endDate) revert StakingPeriodEnded();
        
        // Check if deposit would exceed max capacity
        if (totalAssets() + assets > maxCapacity) revert MaxCapacityReached();
        
        // Get current stake info
        UserStake storage userStake = userStakes[receiver];
        
        // Calculate new weighted timestamp
        if (userStake.amount > 0) {
            // Calculate weighted timestamp: (oldAmount * oldTimestamp + newAmount * currentTimestamp) / totalAmount
            uint256 totalAmount = userStake.amount.add(assets);
            uint256 weightedTimestamp = userStake.amount.mul(userStake.weightedTimestamp).add(
                assets.mul(block.timestamp)
            ).div(totalAmount);
            
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
        if (block.timestamp < endDate) revert CannotWithdrawBeforeEndDate();
        
        _handleRewardsAndReset(owner, receiver);
        
        // Call parent withdraw function to handle the actual token transfer and share burning
        return super.withdraw(assets, receiver, owner);
    }
    
    // Override redeem function to prevent redemptions before end date
    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256) {
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
        if (block.timestamp >= endDate) {
            return 0;
        }
        
        uint256 currentAssets = totalAssets();
        if (currentAssets >= maxCapacity) {
            return 0;
        }
        
        uint256 remainingCapacity = maxCapacity - currentAssets;
        return remainingCapacity < super.maxDeposit(receiver) ? remainingCapacity : super.maxDeposit(receiver);
    }
    
    /**
     * @notice Returns the maximum amount of shares that can be minted
     * param _receiver The address that would receive the shares (unused)
     * @return The maximum amount of shares that can be minted
     */
    function maxMint(address /* _receiver */) public view override returns (uint256) {
        if (block.timestamp >= endDate) {
            return 0;
        }
        
        uint256 currentAssets = totalAssets();
        if (currentAssets >= maxCapacity) {
            return 0;
        }
        
        uint256 remainingCapacity = maxCapacity - currentAssets;
        return _convertToShares(remainingCapacity, MathUpgradeable.Rounding.Down);
    }
    
    // Calculate rewards based on amount staked and time staked
    function calculateRewards(address user) public view returns (uint256) {
        UserStake storage userStake = userStakes[user];
        
        if (userStake.amount == 0) {
            return 0;
        }
        
        // Calculate staking duration (capped at end date)
        uint256 stakingEndTime = block.timestamp < endDate ? block.timestamp : endDate;
        uint256 stakingDuration = stakingEndTime.sub(userStake.weightedTimestamp);
        
        // Calculate rewards: amount * rate * duration / (365 days * 100)
        // This assumes rewardRate is in percentage per year
        return userStake.amount.mul(rewardRate).mul(stakingDuration).div(365 days).div(100);
    }
    
    // Get user's staking information
    function getUserStakeInfo(address user) external view returns (
        uint256 amount,
        uint256 weightedTimestamp,
        uint256 pendingRewards) 
    {
        UserStake storage userStake = userStakes[user];
        return (userStake.amount, userStake.weightedTimestamp, calculateRewards(user));
    }

    /* ============ Internal Functions ============ */

    // Helper function to handle rewards and reset user stake data
    function _handleRewardsAndReset(address owner, address receiver) internal {
        // Calculate and transfer rewards
        uint256 rewards = calculateRewards(owner);
        if (rewards > 0) {
            rewardToken.safeTransfer(receiver, rewards);
            emit RewardsDistributed(receiver, rewards);
        }
        
        // Reset user stake data
        delete userStakes[owner];
    }

}

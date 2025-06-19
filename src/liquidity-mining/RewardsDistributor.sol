// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin-5.0.1/contracts/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin-5.0.1/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin-5.0.1/contracts/utils/structs/EnumerableSet.sol";

import {IKintoWalletFactory} from "@kinto-core/interfaces/IKintoWalletFactory.sol";

import "forge-std/console2.sol";

/**
 * @title Rewards Distributor
 * @notice Distributes rewards using a Merkle tree for verification.
 * @dev This contract handles the distribution of Kinto tokens as rewards and manages Engen token conversions.
 */
contract RewardsDistributor is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ============ Events ============ */

    /**
     * @notice Emitted when the bonus amount is updated.
     * @param newBonusAmount The new bonus amount.
     * @param oldBonusAmount The old bonus amount.
     */
    event BonusAmountUpdated(uint256 indexed newBonusAmount, uint256 indexed oldBonusAmount);

    /**
     * @notice Updates a root of the merkle tree.
     * @param newRoot The new root.
     * @param oldRoot The old root.
     */
    event RootUpdated(bytes32 indexed newRoot, bytes32 indexed oldRoot);

    /**
     * @notice Emitted once `user` claims `amount` of tokens.
     * @param user The user which claimed.
     * @param amount Amount of tokens claimed.
     */
    event UserClaimed(address indexed user, uint256 indexed amount);

    /**
     * @notice Emitted once `user` claims Engen rewards.
     * @param user The user which claimed.
     * @param amount Amount of tokens claimed.
     */
    event UserEngenClaimed(address indexed user, uint256 indexed amount);

    /**
     * @notice Emitted once `user` claims the new user reward.
     * @param user The user which claimed.
     * @param amount Amount of tokens claimed.
     */
    event NewUserReward(address indexed user, uint256 indexed amount);

    /**
     * @notice Emitted when an address is added to the whitelist to bypass claim limits.
     * @param account The account added to the whitelist.
     */
    event WalletClaimWhitelistAdded(address indexed account);

    /**
     * @notice Emitted when an address is removed from the whitelist.
     * @param account The account removed from the whitelist.
     */
    event WalletClaimWhitelistRemoved(address indexed account);

    /* ============ Errors ============ */

    /**
     * @notice Thrown when the maximum limit for token distribution is exceeded.
     * @param amount The amount attempted to be claimed.
     * @param limit The maximum allowable limit.
     */
    error MaxLimitReached(uint256 amount, uint256 limit);

    /**
     * @notice Thrown when the provided proof does not match the leaf.
     * @param proof The provided proof.
     * @param leaf The leaf node.
     */
    error InvalidProof(bytes32[] proof, bytes32 leaf);

    /**
     * @notice Thrown when the caller is not the walletFactory.
     * @param caller The caller address.
     */
    error OnlyWalletFactory(address caller);

    /**
     * @notice Thrown when the Engen rewards already claimed by the user.
     * @param user The user address.
     */
    error EngenAlreadyClaimed(address user);

    /**
     * @notice Thrown when the current root already claimed by the user.
     * @param user The user address.
     */
    error RootAlreadyClaimed(address user);

    /**
     * @notice Thrown when all tokens already claimed by user.
     * @param user The user address.
     */
    error AlreadyClaimed(address user);

    /**
     * @notice Thrown when daily claim limit is exceeded.
     * @param amount The amount attempted to be claimed.
     * @param limit The daily limit.
     * @param available The amount still available to claim today.
     */
    error DailyLimitExceeded(uint256 amount, uint256 limit, uint256 available);

    /* ============ Constants & Immutables ============ */

    /// @notice Role to update the root.
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE ");

    /// @notice Starting time of the mining program.
    uint256 public immutable startTime;

    /// @notice The address of Kinto token.
    IERC20 public immutable KINTO;

    /// @notice The address of Kinto Wallet Factory.
    address public immutable walletFactory;

    /// @notice Total amount of tokens to give away during liquidity mining. 4 million tokens.
    uint256 public constant totalTokens = 4_000_000 * 1e18;

    /// @notice Total number of quarters 40 == 10 years.
    uint256 public constant quarters = 10 * 4;

    /// @notice New user rewards in K tokens upon wallet creation.
    uint256 public constant NEW_USER_REWARD = 1 * 1e18;

    /// @notice New user rewards timestmap
    uint256 public constant NEW_USER_REWARD_TIMESTAMP = 1729785402;

    /// @notice New user rewards end timestmap
    uint256 public constant NEW_USER_REWARD_END_TIMESTAMP = 1734133547;

    /// @notice Daily claim limit per user in K tokens (5000 tokens)
    uint256 public constant DAILY_CLAIM_LIMIT = 5000 * 1e18;

    /// @notice One day in seconds (24 hours)
    uint256 public constant ONE_DAY = 24 * 60 * 60;

    /// @notice Treasury address
    address public constant TREASURY = 0x793500709506652Fcc61F0d2D0fDa605638D4293;

    /* ============ State Variables ============ */

    /// @notice The root of the merkle tree for Kinto token distribition.
    bytes32 public root;

    /// @notice Total amount of claimed tokens.
    uint256 public totalClaimed;

    /// @notice Returns the amount of tokens claimed by a user.
    mapping(address => uint256) private _claimedByUser;

    /// @notice Amount of funds preloaded at the start.
    uint256 public bonusAmount;

    /// @notice DEPRECATED: Engen users which kept the capital.
    mapping(address => bool) private __engenHolders;

    /// @notice DEPRECATED: Total amount of Kinto claimed tokens from Engen program.
    uint256 private __totalKintoFromEngenClaimed;

    /// @notice Rewards per quarter for liquidity mining.
    mapping(uint256 => uint256) public rewardsPerQuarter;

    /// @notice DEPRECATED: Whenever user claimed Engen rewards or not.
    mapping(address => bool) private __hasClaimedEngen;

    // Mapping to track which root a user has claimed for.
    mapping(address => bytes32) public claimedRoot;

    /// @notice Mapping to track last claim timestamp for each user
    mapping(address => uint256) public lastClaimTimestamp;

    /// @notice Mapping to track amount claimed by user for the current day
    mapping(address => uint256) public dailyClaimedAmount;

    /// @notice Set of addresses that are exempt from daily claim limits
    EnumerableSet.AddressSet private _claimWhitelistedAddresses;

    /* ============ Constructor ============ */

    /**
     * @notice Initializes the contract with the given parameters.
     * @param kinto_ The address of the Kinto token.
     * @param startTime_ The starting time of the mining program.
     */
    constructor(IERC20 kinto_, uint256 startTime_, address walletFactory_) {
        _disableInitializers();

        KINTO = kinto_;
        startTime = startTime_;
        walletFactory = walletFactory_;
    }

    /**
     * @notice Initialize the proxy.
     * @param root_ The initial root of the Merkle tree.
     * @param bonusAmount_ The initial bonus amount of tokens.
     */
    function initialize(bytes32 root_, uint256 bonusAmount_) external virtual initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, msg.sender);

        root = root_;
        bonusAmount = bonusAmount_;

        // Initialize the variable to track the total rewards spent until the current quarter
        uint256 rewardsSpentUntilE;
        // Loop through each quarter from 1 to the total number of quarters
        for (uint256 e = 1; e <= quarters; e++) {
            // Initialize the diminishing factor to 1e18
            uint256 diminishingFactor = 1e18;

            // Apply the diminishing factor for each previous quarter
            for (uint256 i = 0; i < e; i++) {
                diminishingFactor = (diminishingFactor * 100) / 105;
            }

            // Calculate the reward factor for the current quarter
            uint256 rpFactor = totalTokens * diminishingFactor / 1e18;

            // Calculate the rewards for the current quarter by subtracting the reward factor and previously spent rewards from the total tokens
            uint256 rewardsForQuarter = totalTokens - rpFactor - rewardsSpentUntilE;

            // Store the calculated rewards for the current quarter in the rewardsPerQuarter mapping
            rewardsPerQuarter[e - 1] = rewardsForQuarter;

            // Update the total rewards spent until the current quarter
            rewardsSpentUntilE += rewardsForQuarter;
        }
    }

    /**
     * @dev Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the factory is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {
        (newImplementation);
    }

    /* ============ External ============ */

    /**
     * @notice Allows a user to claim tokens if they provide a valid proof.
     * @param proof The Merkle proof.
     * @param user The address of the user claiming tokens.
     * @param totalUserTokens The total amount of tokens to claim.
     */
    function claim(bytes32[] memory proof, address user, uint256 totalUserTokens) external nonReentrant {
        // Do not allow to claim from the same root twice.
        if (claimedRoot[user] == root) {
            revert RootAlreadyClaimed(user);
        }

        // Check if user has any tokens to claim.
        if (totalUserTokens <= claimedByUser(user)) {
            revert AlreadyClaimed(user);
        }

        // Generate the leaf node from the user's address and the amount they are claiming
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(user, totalUserTokens))));

        // Verify the provided proof against the stored Merkle root
        if (MerkleProof.verify(proof, root, leaf) == false) {
            revert InvalidProof(proof, leaf);
        }

        uint256 amount = totalUserTokens - claimedByUser(user);

        // Check if the total claimed amount exceeds the allowable limit
        if (amount > getUnclaimedLimit()) {
            revert MaxLimitReached(totalClaimed + amount, getTotalLimit());
        }

        // Check and update daily claim limits, returns actual amount respecting daily limits
        uint256 actualAmount = checkAndUpdateDailyLimit(user, amount);

        // Update the total claimed amount and the amount claimed by the user
        totalClaimed += actualAmount;
        _claimedByUser[user] += actualAmount;

        // Mark current root as claimed for the user
        claimedRoot[user] = root;

        // Transfer the claimed tokens to the user
        KINTO.safeTransfer(user, actualAmount);

        // Emit an event indicating that the user has claimed tokens
        emit UserClaimed(user, actualAmount);
    }

    /**
     * @notice Does nothing. Remove upon the upgrade of KintoWalletFactory
     */
    function newUserClaim(address) external {}

    /**
     * @notice Updates the root of the Merkle tree.
     * @param newRoot The new root.
     */
    function updateRoot(bytes32 newRoot) external onlyRole(UPDATER_ROLE) {
        emit RootUpdated(newRoot, root);
        root = newRoot;
    }

    /**
     * @notice Updates the bonus amount of tokens.
     * @param newBonusAmount The new bonus amount.
     */
    function updateBonusAmount(uint256 newBonusAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit BonusAmountUpdated(newBonusAmount, bonusAmount);
        bonusAmount = newBonusAmount;
    }

    /**
     * @notice Adds an address to the whitelist to bypass daily claim limits
     * @param account The address to whitelist
     */
    function addToClaimWhitelist(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _claimWhitelistedAddresses.add(account);
        emit WalletClaimWhitelistAdded(account);
    }

    /**
     * @notice Removes an address from the whitelist
     * @param account The address to remove from whitelist
     */
    function removeFromClaimWhitelist(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _claimWhitelistedAddresses.remove(account);
        emit WalletClaimWhitelistRemoved(account);
    }

    /**
     * @notice Checks if an address is whitelisted to bypass daily claim limits
     * @param account The address to check
     * @return true if the address is whitelisted
     */
    function isClaimWhitelisted(address account) external view returns (bool) {
        return _claimWhitelistedAddresses.contains(account);
    }

    /**
     * @notice Returns an array of all claim whitelisted wallets
     * @return An array of claim whitelist wallets
     */
    function claimWhitelist() external view returns (address[] memory) {
        return _claimWhitelistedAddresses.values();
    }

    /**
     * @notice Transfer the given amount of K tokens to the treasury - only the default admin can do this
     * @param amount The amount of K tokens to transfer
     */
    function transferToTreasury(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        KINTO.safeTransfer(TREASURY, amount);
    }

    /* ============ View ============ */

    /**
     * @notice Returns the total limit of tokens that can be distributed based on quarterly rewards at the specific time.
     * @param time The time at which rewards are calculated.
     * @return The total limit of tokens.
     */
    function getTotalLimit(uint256 time) public view returns (uint256) {
        return getRewards(time) + bonusAmount;
    }

    /**
     * @notice Returns the total limit of tokens that can be distributed based on quarterly rewards.
     * @return The total limit of tokens.
     */
    function getTotalLimit() public view returns (uint256) {
        return getTotalLimit(block.timestamp);
    }

    /**
     * @notice Calculates the total rewards available at a specific time.
     * @param time The time at which to calculate the rewards.
     * @return The total rewards available.
     */
    function getRewards(uint256 time) public view returns (uint256) {
        if (time < startTime) {
            return 0;
        }

        // Calculate the number of seconds since the start of the program
        uint256 elapsedTime = time - startTime;

        // Calculate the current quarter based on the elapsed time
        uint256 currentQuarter = elapsedTime / (90 days); // Approximate each quarter as 90 days

        // Sum the rewards up to the previous quarter
        uint256 totalLimit;

        // Ensure we do not exceed the total number of quarters
        if (currentQuarter < quarters) {
            for (uint256 i = 0; i < currentQuarter; i++) {
                totalLimit += rewardsPerQuarter[i];
            }

            // Calculate the time passed in the current quarter
            // slither-disable-next-line weak-prng
            uint256 timePassedInCurrentQuarter = elapsedTime % (90 days);
            uint256 currentQuarterReward = rewardsPerQuarter[currentQuarter];
            uint256 currentQuarterLimit = (currentQuarterReward * timePassedInCurrentQuarter) / (90 days);
            // Add the partial reward for the current quarter
            totalLimit += currentQuarterLimit;
        } else {
            // if we are past 10 years, just return the total number of tokens for liquidity mining program.
            totalLimit += totalTokens;
        }

        return totalLimit;
    }

    /**
     * @notice Calculates the rewards accrued between two time points.
     * @param fromTime The starting time for the calculation.
     * @param toTime The ending time for the calculation.
     * @return The rewards accrued between fromTime and toTime.
     */
    function getRewards(uint256 fromTime, uint256 toTime) public view returns (uint256) {
        return getRewards(toTime) - getRewards(fromTime);
    }

    /**
     * @notice Returns the remaining unclaimed limit of tokens.
     * @return The remaining unclaimed limit of tokens.
     */
    function getUnclaimedLimit() public view returns (uint256) {
        return getTotalLimit() - totalClaimed;
    }

    /**
     * @notice Returns the amount claimed by the user.
     * @return The amount claimed by the user.
     */
    function claimedByUser(address wallet) public view returns (uint256) {
        uint256 claimed = _claimedByUser[wallet];
        uint256 walletTs = IKintoWalletFactory(walletFactory).getWalletTimestamp(wallet);
        if (walletTs >= NEW_USER_REWARD_TIMESTAMP && walletTs < NEW_USER_REWARD_END_TIMESTAMP) {
            // Offset K bonus for new users after the launch of the rewards program
            return claimed >= NEW_USER_REWARD ? claimed - NEW_USER_REWARD : claimed;
        }
        return claimed;
    }

    /**
     * @notice Returns the amount of tokens a user can still claim today
     * @param user The address of the user
     * @return The amount of tokens still claimable today, or the maximum uint256 value if the user is whitelisted
     */
    function getDailyRemainingClaimable(address user) public view returns (uint256) {
        // If user is whitelisted, they can claim any amount
        if (_claimWhitelistedAddresses.contains(user)) {
            return type(uint256).max;
        }

        // If the user has never claimed or this is a new day, user has the full daily limit available
        if (lastClaimTimestamp[user] == 0 || block.timestamp >= lastClaimTimestamp[user] + ONE_DAY) {
            return DAILY_CLAIM_LIMIT;
        }

        // Calculate current day based on timestamp
        uint256 currentDay = block.timestamp / ONE_DAY;
        uint256 lastClaimDay = lastClaimTimestamp[user] / ONE_DAY;

        // If this is a new day, user has the full daily limit available
        if (currentDay > lastClaimDay) {
            return DAILY_CLAIM_LIMIT;
        }

        // If user has claimed less than the daily limit, return remaining amount
        if (dailyClaimedAmount[user] < DAILY_CLAIM_LIMIT) {
            return DAILY_CLAIM_LIMIT - dailyClaimedAmount[user];
        }

        // User has already claimed the full daily limit
        return 0;
    }

    /**
     * @notice Checks if a claim amount is within daily limits and updates tracking state
     * If amount exceeds the daily limit, it transfers the available limit instead
     * Whitelisted addresses bypass the daily limit check
     * @param user The address of the user claiming tokens
     * @param amount The amount being claimed
     * @return actualAmount The actual amount that will be claimed (limited by daily limit if necessary)
     */
    function checkAndUpdateDailyLimit(address user, uint256 amount) internal returns (uint256 actualAmount) {
        // If user is whitelisted, bypass daily limit check
        if (_claimWhitelistedAddresses.contains(user)) {
            // Still update timestamps for tracking purposes
            lastClaimTimestamp[user] = block.timestamp;
            dailyClaimedAmount[user] += amount;
            return amount;
        }

        // Calculate current day based on timestamp
        uint256 currentDay = block.timestamp / ONE_DAY;
        uint256 lastClaimDay = lastClaimTimestamp[user] == 0 ? 0 : lastClaimTimestamp[user] / ONE_DAY;

        // Reset daily claim counter if it's a new day or first claim
        if (lastClaimTimestamp[user] == 0 || currentDay > lastClaimDay) {
            dailyClaimedAmount[user] = 0;
        }

        // Calculate how much the user can still claim today
        uint256 remainingDaily = getDailyRemainingClaimable(user);

        // If trying to claim more than allowed, limit to the remaining daily amount
        if (amount > remainingDaily) {
            actualAmount = remainingDaily;
        } else {
            actualAmount = amount;
        }

        // Update the daily claimed amount and last claim timestamp
        dailyClaimedAmount[user] += actualAmount;
        lastClaimTimestamp[user] = block.timestamp;
    }
}

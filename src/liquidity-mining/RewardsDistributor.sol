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

import {IKintoWalletFactory} from "@kinto-core/interfaces/IKintoWalletFactory.sol";

import "forge-std/console2.sol";

/**
 * @title Rewards Distributor
 * @notice Distributes rewards using a Merkle tree for verification.
 * @dev This contract handles the distribution of Kinto tokens as rewards and manages Engen token conversions.
 */
contract RewardsDistributor is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

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

        // Update the total claimed amount and the amount claimed by the user
        totalClaimed += amount;
        _claimedByUser[user] += amount;

        // Mark current root as claimed for the user
        claimedRoot[user] = root;

        // Transfer the claimed tokens to the user
        KINTO.safeTransfer(user, amount);

        // Emit an event indicating that the user has claimed tokens
        emit UserClaimed(user, amount);
    }

    /**
     * @notice Allows a new user to claim the new user reward.
     * @param wallet The address of the wallet to claim the reward for.
     */
    function newUserClaim(address wallet) external nonReentrant {
        if (msg.sender != walletFactory) {
            revert OnlyWalletFactory(msg.sender);
        }
        if (_claimedByUser[wallet] > 0) {
            revert AlreadyClaimed(wallet);
        }
        _claimedByUser[wallet] += NEW_USER_REWARD;
        totalClaimed += NEW_USER_REWARD;
        KINTO.safeTransfer(wallet, NEW_USER_REWARD);
        emit NewUserReward(wallet, NEW_USER_REWARD);
    }

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
        if (IKintoWalletFactory(walletFactory).getWalletTimestamp(wallet) >= NEW_USER_REWARD_TIMESTAMP) {
            // Offset K bonus for new users after the launch of the rewards program
            return claimed >= NEW_USER_REWARD ? claimed - NEW_USER_REWARD : claimed;
        }
        return claimed;
    }
}

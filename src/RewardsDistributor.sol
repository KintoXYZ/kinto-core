// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin-5.0.1/contracts/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuard} from "@openzeppelin-5.0.1/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";

/**
 * @title Rewards Distributor
 * @notice Distributes rewards using a Merkle tree for verification.
 */
contract RewardsDistributor is ReentrancyGuard, Ownable {
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

    event UserEngenClaimed(address indexed user, uint256 indexed amount);

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

    /* ============ Constants & Immutables ============ */

    /// @notice Starting time of the mining program.
    uint256 public immutable startTime;

    /// @notice The address of Kinto token.
    IERC20 public immutable KINTO;

    /// @notice The address of ENGEN token.
    IERC20 public immutable ENGEN;

    /// @notice The multiplier to convert Engen tokens to Kinto tokens.
    uint256 public constant ENGEN_MULTIPLIER = 22e16;

    /// @notice The bonus given to Engen holders.
    uint256 public constant ENGEN_HOLDER_BONUS = 25e16;

    /// @notice Total amount of tokens to give away during liquidity mining. 4 million tokens.
    uint256 public constant totalTokens = 4_000_000 * 1e18;

    /// @notice Total number of quarters 40 == 10 years.
    uint256 public constant quarters = 10 * 4;

    /* ============ State Variables ============ */

    /// @notice The root of the merkle tree for Kinto token distribition.
    bytes32 public root;

    /// @notice Total amount of claimed tokens.
    uint256 public totalClaimed;

    /// @notice Returns the amount of tokens claimed by a user.
    mapping(address => uint256) public claimedByUser;

    /// @notice Amount of funds preloaded at the start.
    uint256 public bonusAmount;

    /// @notice Engen users which kept the capital.
    mapping(address => bool) public engenHolders;

    /// @notice Total amount of Kinto claimed tokens from Engen program.
    uint256 public totalKintoFromEngenClaimed;

    /// @notice Rewards per quarter for liquidity mining.
    mapping(uint256 => uint256) public rewardsPerQuarter;

    /* ============ Constructor ============ */

    /**
     * @notice Initializes the contract with the given parameters.
     * @param kinto_ The address of the Kinto token.
     * @param root_ The initial root of the Merkle tree.
     * @param bonusAmount_ The initial bonus amount of tokens.
     * @param startTime_ The starting time of the mining program.
     */
    constructor(IERC20 kinto_, IERC20 engen_, bytes32 root_, uint256 bonusAmount_, uint256 startTime_)
        Ownable(msg.sender)
    {
        KINTO = kinto_;
        ENGEN = engen_;
        root = root_;
        bonusAmount = bonusAmount_;
        startTime = startTime_;

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

    /* ============ External ============ */

    /**
     * @notice Allows a user to claim tokens if they provide a valid proof.
     * @param proof The Merkle proof.
     * @param user The address of the user claiming tokens.
     * @param amount The amount of tokens to claim.
     */
    function claim(bytes32[] memory proof, address user, uint256 amount) external nonReentrant {
        // Generate the leaf node from the user's address and the amount they are claiming
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(user, amount))));

        // Verify the provided proof against the stored Merkle root
        if (MerkleProof.verify(proof, root, leaf) == false) {
            revert InvalidProof(proof, leaf);
        }

        // Check if the total claimed amount exceeds the allowable limit
        if (amount > getUnclaimedLimit()) {
            revert MaxLimitReached(totalClaimed + amount, getTotalLimit());
        }

        // Update the total claimed amount and the amount claimed by the user
        totalClaimed += amount;
        claimedByUser[user] += amount;

        // Transfer the claimed tokens to the user
        KINTO.safeTransfer(user, amount);

        // Emit an event indicating that the user has claimed tokens
        emit UserClaimed(user, amount);
    }

    /**
     * @notice Allows a user to claim Kinto tokens based on their Engen token balance.
     * @dev The amount of Kinto tokens claimed is calculated based on the user's Engen token balance and a multiplier.
     *      Engen holders receive an additional bonus if they are marked as such.
     */
    function claimEngen() external nonReentrant {
        // Amount of Kinto tokens to claim is EngenBalance * multiplier
        uint256 amount = ENGEN.balanceOf(msg.sender) * ENGEN_MULTIPLIER / 1e18;

        // Engen holder get an extra holder bonus
        amount = engenHolders[msg.sender] ? amount * ENGEN_HOLDER_BONUS / 1e18 : amount;

        totalKintoFromEngenClaimed += amount;

        // Transfer Kinto tokens to the user
        KINTO.safeTransfer(msg.sender, amount);

        // Emit an event indicating that the user has claimed tokens
        emit UserEngenClaimed(msg.sender, amount);
    }

    /**
     * @notice Updates the list of Engen holders and their status.
     * @dev Only the contract owner can call this function.
     * @param users The list of user addresses to update.
     * @param values The corresponding list of boolean values indicating whether each user is an Engen holder.
     */
    function updateEngenHolders(address[] memory users, bool[] memory values) external onlyOwner {
        for (uint256 index = 0; index < users.length; index++) {
            engenHolders[users[index]] = values[index];
        }
    }

    /**
     * @notice Updates the root of the Merkle tree.
     * @param newRoot The new root.
     */
    function updateRoot(bytes32 newRoot) external onlyOwner {
        emit RootUpdated(newRoot, root);
        root = newRoot;
    }

    /**
     * @notice Updates the bonus amount of tokens.
     * @param newBonusAmount The new bonus amount.
     */
    function updateBonusAmount(uint256 newBonusAmount) external onlyOwner {
        emit BonusAmountUpdated(newBonusAmount, bonusAmount);
        bonusAmount = newBonusAmount;
    }

    /* ============ View ============ */

    /**
     * @notice Returns the total limit of tokens that can be distributed based on quarterly rewards.
     * @return The total limit of tokens.
     */
    function getTotalLimit() public view returns (uint256) {
        if (block.timestamp < startTime) {
            return 0;
        }

        // Calculate the number of seconds since the start of the program
        uint256 elapsedTime = block.timestamp - startTime;

        // Calculate the current quarter based on the elapsed time
        uint256 currentQuarter = elapsedTime / (90 days); // Approximate each quarter as 90 days

        // Ensure we do not exceed the total number of quarters
        if (currentQuarter >= quarters) {
            currentQuarter = quarters - 1;
        }

        // Sum the rewards up to the previous quarter
        uint256 totalLimit = 0;
        for (uint256 i = 0; i < currentQuarter; i++) {
            totalLimit += rewardsPerQuarter[i];
        }

        // Calculate the time passed in the current quarter
        uint256 timePassedInCurrentQuarter = elapsedTime % (90 days);
        uint256 currentQuarterReward = rewardsPerQuarter[currentQuarter];
        uint256 currentQuarterLimit = (currentQuarterReward * timePassedInCurrentQuarter) / (90 days);

        // Add the partial reward for the current quarter
        totalLimit += currentQuarterLimit;

        // Add the bonus amount
        totalLimit += bonusAmount;

        return totalLimit;
    }

    /**
     * @notice Returns the remaining unclaimed limit of tokens.
     * @return The remaining unclaimed limit of tokens.
     */
    function getUnclaimedLimit() public view returns (uint256) {
        return getTotalLimit() - totalClaimed;
    }
}

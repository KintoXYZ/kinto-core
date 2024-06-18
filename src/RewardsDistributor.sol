// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin-5.0.1/contracts/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuard} from "@openzeppelin-5.0.1/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";

/**
 * @title Rewards Distributor
 */
contract RewardsDistributor is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /* ============ Events ============ */

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

    /* ============ Errors ============ */

    /// @notice The limit for maximum amount of tokens to distribute have been exceeded.
    error MaxLimitReached(uint256 amount, uint256 limit);

    /// @notice The proof doesn't match the leaf.
    error InvalidProof(bytes32[] proof, bytes32 leaf);

    /* ============ Constants & Immutables ============ */

    /// @notice Amount of funds for ENGEN program.
    uint256 public immutable engenFunds;

    /// @notice The maximum rate of token per second which can be distributed.
    uint256 public immutable maxRatePerSecond;

    /// @notice Starting time of the mining program.
    uint256 public immutable startTime;

    /// @notice The address of Kinto token to distribute.
    IERC20 public immutable KINTO;

    /* ============ State Variables ============ */
    /// @notice The root of the merkle tree for Kinto token distribition.
    bytes32 public root;

    /// @notice Total amount of claimed tokens.
    uint256 public totalClaimed;

    /// @notice Returns the amount of tokens claimed by a user.
    mapping(address => uint256) public claimedByUser;

    /* ============ Constructor ============ */

    constructor(
        IERC20 kinto_,
        bytes32 root_,
        uint256 engenFunds_,
        uint256 maxRatePerSecond_,
        uint256 startTime_
    ) Ownable(msg.sender) {
        KINTO = kinto_;
        root = root_;
        engenFunds = engenFunds_;
        maxRatePerSecond = maxRatePerSecond_;
        startTime = startTime_;
    }

    /* ============ External ============ */

    function claim(bytes32[] memory proof, address user, uint256 amount) external nonReentrant {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(user, amount))));
        if (MerkleProof.verify(proof, root, leaf) == false) {
            revert InvalidProof(proof, leaf);
        }
        if (totalClaimed + amount > maxRatePerSecond * (block.timestamp - startTime) + engenFunds) {
            revert MaxLimitReached(totalClaimed + amount, maxRatePerSecond * (block.timestamp - startTime) + engenFunds);
        }

        totalClaimed += amount;
        claimedByUser[user] += amount;

        KINTO.safeTransfer(user, amount);

        emit UserClaimed(user, amount);
    }

    function updateRoot(bytes32 newRoot) external onlyOwner {
        emit RootUpdated(newRoot, root);
        root = newRoot;
    }
}

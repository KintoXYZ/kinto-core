// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin-5.0.1/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin-5.0.1/contracts/utils/cryptography/MerkleProof.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SealedBidTokenSale
 * @dev Sealed-bid auction-style token sale with USDC deposits and Merkle-based claims.
 *      Features time-bound participation, minimum/maximum caps, and non-custodial withdrawals.
 */
contract SealedBidTokenSale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ============ Custom Errors ============ */

    /// @notice Invalid sale token address provided (zero address)
    error InvalidSaleTokenAddress(address token);
    /// @notice Invalid treasury address provided (zero address)
    error InvalidTreasuryAddress(address treasury);
    /// @notice Sale period has not started yet
    error SaleNotStarted(uint256 currentTime, uint256 startTime);
    /// @notice Sale period has already ended
    error SaleAlreadyEnded(uint256 currentTime);
    /// @notice Sale period has not ended yet
    error SaleNotEnded(uint256 currentTime);
    /// @notice Operation requires capReached sale state
    error SaleNotSuccessful();
    /// @notice Operation requires failed sale state
    error SaleWasSuccessful();
    /// @notice Deposited amount must be greater than zero
    error ZeroDeposit();
    /// @notice No funds available for withdrawal
    error NothingToWithdraw(address user);
    /// @notice Tokens have already been claimed
    error AlreadyClaimed(address user);
    /// @notice Provided Merkle proof is invalid
    error InvalidProof(bytes32[] proof, bytes32 leaf);
    /// @notice Merkle root not set for claims
    error MerkleRootNotSet();

    /* ============ Events ============ */

    /// @notice Emitted on USDC deposit
    event Deposited(address indexed user, uint256 amount);
    /// @notice Emitted on USDC withdrawal
    event Withdrawn(address indexed user, uint256 amount);
    /// @notice Emitted when sale is ended
    event SaleEnded(bool capReached, uint256 totalDeposited);
    /// @notice Emitted when Merkle root is set
    event MerkleRootSet(bytes32 root);
    /// @notice Emitted on capReached token claim
    event Claimed(address indexed user, uint256 tokenAmount);

    /* ============ Immutable Parameters ============ */

    /// @notice Sale token contract
    IERC20 public immutable saleToken;
    /// @notice USDC token contract
    IERC20 public immutable USDC;
    /// @notice Treasury address for proceeds
    address public immutable treasury;
    /// @notice Sale start timestamp
    uint256 public immutable startTime;
    /// @notice Minimum USDC required for success
    uint256 public immutable minimumCap;

    /* ============ State Variables ============ */

    /// @notice Sale finalization status
    bool public saleEnded;
    /// @notice Sale success status
    bool public capReached;
    /// @notice Total USDC deposited
    uint256 public totalDeposited;
    /// @notice Merkle root for allocations
    bytes32 public merkleRoot;
    /// @notice User deposits tracking
    mapping(address => uint256) public deposits;
    /// @notice Claims tracking
    mapping(address => bool) public hasClaimed;

    /* ============ Constructor ============ */

    /**
     * @notice Initialize sale parameters
     * @param _saleToken Sale token address
     * @param _treasury Treasury address for proceeds
     * @param _usdcToken USDC token address
     * @param _startTime Sale start timestamp
     * @param _minimumCap Minimum USDC for success
     */
    constructor(address _saleToken, address _treasury, address _usdcToken, uint256 _startTime, uint256 _minimumCap)
        Ownable(msg.sender)
    {
        if (_saleToken == address(0)) revert InvalidSaleTokenAddress(_saleToken);
        if (_treasury == address(0)) revert InvalidTreasuryAddress(_treasury);

        saleToken = IERC20(_saleToken);
        treasury = _treasury;
        USDC = IERC20(_usdcToken);
        startTime = _startTime;
        minimumCap = _minimumCap;
    }

    /* ============ User Functions ============ */

    /**
     * @notice Deposited USDC into the sale
     * @param amount Amount of USDC to deposit
     */
    function deposit(uint256 amount) external nonReentrant {
        if (block.timestamp < startTime) revert SaleNotStarted(block.timestamp, startTime);
        if (saleEnded) revert SaleAlreadyEnded(block.timestamp);
        if (amount == 0) revert ZeroDeposit();

        USDC.safeTransferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] += amount;
        totalDeposited += amount;

        emit Deposited(msg.sender, amount);
    }

    /**
     * @notice Withdrawn USDC if sale failed
     */
    function withdraw() external nonReentrant {
        if (!saleEnded) revert SaleNotEnded(block.timestamp);
        if (capReached) revert SaleWasSuccessful();

        uint256 amount = deposits[msg.sender];
        if (amount == 0) revert NothingToWithdraw(msg.sender);

        deposits[msg.sender] = 0;
        USDC.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Claimed allocated tokens using Merkle proof
     * @param saleTokenAllocation Token amount allocated to sender
     * @param proof Merkle proof for allocation
     */
    function claimTokens(uint256 saleTokenAllocation, uint256 usdcAllocation, bytes32[] calldata proof)
        external
        nonReentrant
    {
        if (!saleEnded || !capReached) revert SaleNotSuccessful();
        if (merkleRoot == bytes32(0)) revert MerkleRootNotSet();
        if (hasClaimed[msg.sender]) revert AlreadyClaimed(msg.sender);

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, saleTokenAllocation, usdcAllocation));
        if (!MerkleProof.verify(proof, merkleRoot, leaf)) revert InvalidProof(proof, leaf);

        hasClaimed[msg.sender] = true;

        if (saleTokenAllocation > 0) {
            saleToken.safeTransfer(msg.sender, saleTokenAllocation);
        }

        if (usdcAllocation > 0) {
            USDC.safeTransfer(msg.sender, usdcAllocation);
        }

        emit Claimed(msg.sender, saleTokenAllocation);
    }

    /* ============ Admin Functions ============ */

    /**
     * @notice Ends sale
     */
    function endSale() external onlyOwner {
        if (saleEnded) revert SaleAlreadyEnded(block.timestamp);

        saleEnded = true;
        capReached = totalDeposited >= minimumCap;

        emit SaleEnded(capReached, totalDeposited);
    }

    /**
     * @notice Set Merkle root for allocations
     * @param newRoot Root of allocation Merkle tree
     */
    function setMerkleRoot(bytes32 newRoot) external onlyOwner {
        if (!saleEnded || !capReached) revert SaleNotSuccessful();
        merkleRoot = newRoot;
        emit MerkleRootSet(newRoot);
    }

    /**
     * @notice Withdrawn proceeds to treasury
     */
    function withdrawProceeds() external onlyOwner {
        if (!saleEnded || !capReached) revert SaleNotSuccessful();
        USDC.safeTransfer(treasury, USDC.balanceOf(address(this)));
    }
}

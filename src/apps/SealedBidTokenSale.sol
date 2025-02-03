// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin-5.0.1/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin-5.0.1/contracts/utils/cryptography/MerkleProof.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SealedBidTokenSale
 * @notice Manages a sealed-bid token sale where users deposit USDC and receive tokens based on their allocations
 * @dev Implements a non-custodial token sale mechanism with the following features:
 *  - Time-bound participation window
 *  - Minimum cap for sale success
 *  - USDC deposits from users
 *  - Merkle-based token allocation claims
 *  - Full refunds if minimum cap not reached
 */
contract SealedBidTokenSale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ============ Custom Errors ============ */

    /// @notice Thrown when attempting to initialize with zero address for sale token
    error InvalidSaleTokenAddress(address token);
    /// @notice Thrown when attempting to initialize with zero address for treasury
    error InvalidTreasuryAddress(address treasury);
    /// @notice Thrown when attempting operations before sale start time
    error SaleNotStarted(uint256 currentTime, uint256 startTime);
    /// @notice Thrown when attempting operations after sale has ended
    error SaleAlreadyEnded(uint256 currentTime);
    /// @notice Thrown when attempting operations that require sale to be ended
    error SaleNotEnded(uint256 currentTime);
    /// @notice Thrown when attempting operations that require minimum cap to be reached
    error CapNotReached();
    /// @notice Thrown when attempting withdrawals in successful sale
    error SaleWasSuccessful();
    /// @notice Thrown when attempting to deposit zero amount
    error ZeroDeposit();
    /// @notice Thrown when user has no funds to withdraw
    error NothingToWithdraw(address user);
    /// @notice Thrown when attempting to claim tokens more than once
    error AlreadyClaimed(address user);
    /// @notice Thrown when provided Merkle proof is invalid
    error InvalidProof(bytes32[] proof, bytes32 leaf);
    /// @notice Thrown when attempting claims before Merkle root is set
    error MerkleRootNotSet();

    /* ============ Events ============ */

    /// @notice Emitted when a user deposits USDC into the sale
    /// @param user Address of the depositing user
    /// @param amount Amount of USDC deposited
    event Deposited(address indexed user, uint256 amount);

    /// @notice Emitted when a user withdraws USDC from a failed sale
    /// @param user Address of the withdrawing user
    /// @param amount Amount of USDC withdrawn
    event Withdrawn(address indexed user, uint256 amount);

    /// @notice Emitted when the sale is officially ended
    /// @param capReached Whether the minimum cap was reached
    /// @param totalDeposited Total amount of USDC deposited in sale
    event SaleEnded(bool capReached, uint256 totalDeposited);

    /// @notice Emitted when the Merkle root for token allocations is set
    /// @param root New Merkle root value
    event MerkleRootSet(bytes32 root);

    /// @notice Emitted when a user claims their allocated tokens
    /// @param user Address of the claiming user
    /// @param tokenAmount Amount of tokens claimed
    event Claimed(address indexed user, uint256 tokenAmount);

    /* ============ Immutable Parameters ============ */

    /// @notice Token being sold in the sale
    IERC20 public immutable saleToken;
    /// @notice USDC token contract for deposits
    IERC20 public immutable USDC;
    /// @notice Address where sale proceeds will be sent
    address public immutable treasury;
    /// @notice Timestamp when the sale begins
    uint256 public immutable startTime;
    /// @notice Minimum amount of USDC required for sale success
    uint256 public immutable minimumCap;

    /* ============ State Variables ============ */

    /// @notice Whether the sale period has officially ended
    bool public saleEnded;
    /// @notice Whether the minimum cap was reached by end of sale
    bool public capReached;
    /// @notice Running total of USDC deposited into sale
    uint256 public totalDeposited;
    /// @notice Merkle root for verifying token allocations
    bytes32 public merkleRoot;
    /// @notice Maps user addresses to their USDC deposit amounts
    mapping(address => uint256) public deposits;
    /// @notice Maps user addresses to whether they've claimed tokens
    mapping(address => bool) public hasClaimed;

    /* ============ Constructor ============ */

    /**
     * @notice Initializes the token sale with required parameters
     * @param _saleToken Address of the token being sold
     * @param _treasury Address where sale proceeds will be sent
     * @param _usdcToken Address of the USDC token contract
     * @param _startTime Timestamp when sale will begin
     * @param _minimumCap Minimum USDC amount required for sale success
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
     * @notice Allows users to deposit USDC into the token sale
     * @dev - Sale must be active (after start time, before end)
     *      - Amount must be greater than zero
     *      - Updates user's deposit balance and total deposits
     *      - Transfers USDC from user to contract
     * @param amount Amount of USDC to deposit
     */
    function deposit(uint256 amount) external nonReentrant {
        if (block.timestamp < startTime) revert SaleNotStarted(block.timestamp, startTime);
        if (saleEnded) revert SaleAlreadyEnded(block.timestamp);
        if (amount == 0) revert ZeroDeposit();

        deposits[msg.sender] += amount;
        totalDeposited += amount;

        USDC.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposited(msg.sender, amount);
    }

    /**
     * @notice Allows users to withdraw their USDC if sale failed to reach minimum cap
     * @dev - Sale must be ended and minimum cap not reached
     *      - User must have deposited USDC
     *      - Sends full deposit amount back to user
     *      - Sets user's deposit balance to zero
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
     * @notice Allows users to claim their allocated tokens using a Merkle proof
     * @dev - Sale must be ended successfully and Merkle root set
     *      - User must not have claimed already
     *      - Proof must be valid for user's allocation
     *      - Transfers allocated tokens and USDC to user
     * @param saleTokenAllocation Amount of sale tokens allocated to user
     * @param usdcAllocation Amount of USDC allocated to user
     * @param proof Merkle proof verifying the allocation
     * @param user Address of user claiming tokens
     */
    function claimTokens(uint256 saleTokenAllocation, uint256 usdcAllocation, bytes32[] calldata proof, address user)
        external
        nonReentrant
    {
        if (!saleEnded || !capReached) revert CapNotReached();
        if (merkleRoot == bytes32(0)) revert MerkleRootNotSet();
        if (hasClaimed[user]) revert AlreadyClaimed(user);

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(user, saleTokenAllocation, usdcAllocation))));
        if (!MerkleProof.verify(proof, merkleRoot, leaf)) revert InvalidProof(proof, leaf);

        hasClaimed[user] = true;

        if (saleTokenAllocation > 0) {
            saleToken.safeTransfer(user, saleTokenAllocation);
        }

        if (usdcAllocation > 0) {
            USDC.safeTransfer(user, usdcAllocation);
        }

        emit Claimed(user, saleTokenAllocation);
    }

    /* ============ Admin Functions ============ */

    /**
     * @notice Allows owner to officially end the sale
     * @dev - Can only be called once
     *      - Sets final sale status based on minimum cap
     *      - Emits event with final sale results
     */
    function endSale() external onlyOwner {
        if (saleEnded) revert SaleAlreadyEnded(block.timestamp);

        saleEnded = true;
        capReached = totalDeposited >= minimumCap;

        emit SaleEnded(capReached, totalDeposited);
    }

    /**
     * @notice Sets the Merkle root for verifying token allocations
     * @dev - Sale must be ended successfully
     *      - Enables token claiming process
     * @param newRoot The Merkle root hash of all valid allocations
     */
    function setMerkleRoot(bytes32 newRoot) external onlyOwner {
        if (!saleEnded || !capReached) revert CapNotReached();
        merkleRoot = newRoot;
        emit MerkleRootSet(newRoot);
    }

    /**
     * @notice Allows owner to withdraw sale proceeds to treasury
     * @dev - Sale must be ended successfully
     *      - Transfers all USDC to treasury address
     */
    function withdrawProceeds() external onlyOwner {
        if (!saleEnded || !capReached) revert CapNotReached();
        USDC.safeTransfer(treasury, USDC.balanceOf(address(this)));
    }
}

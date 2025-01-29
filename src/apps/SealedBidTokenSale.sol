// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title SealedBidTokenSale
 * @dev A contract to accept USDC deposits for a sealed-bid, multi-unit uniform-price sale
 *      with off-chain price discovery. Participants can deposit multiple times, and if the
 *      sale meets a minimumCap, it is deemed successful. A Merkle root is published later
 *      for token claims. Depositors can withdraw funds if the sale fails.
 *
 *      Proceeds are withdrawn to a predetermined treasury address (set in the constructor).
 */
contract SealedBidTokenSale is Ownable, ReentrancyGuard {
    // -----------------------------------------------------------------------
    // Errors in 0.8 style (custom errors)
    // -----------------------------------------------------------------------
    error SaleNotStarted();
    error SaleEnded();
    error AlreadyFinalized();
    error NotFinalized();
    error SaleNotEnded();
    error SaleNotSuccessful();
    error SaleWasSuccessful();
    error ZeroDeposit();
    error NothingToWithdraw();
    error AlreadyClaimed();
    error InvalidProof();
    error MerkleRootNotSet();

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Finalized(bool successful, uint256 totalDeposited);
    event MerkleRootSet(bytes32 root);
    event Claim(address indexed user, uint256 tokenAmount);

    // -----------------------------------------------------------------------
    // Immutable & Configurable Parameters
    // -----------------------------------------------------------------------
    IERC20 public immutable usdcToken; // Address of USDC token contract
    IERC20 public immutable saleToken;
    address public immutable treasury; // Where proceeds go upon withdrawal

    uint256 public immutable startTime; // Sale start timestamp
    uint256 public immutable endTime; // Sale end timestamp
    uint256 public immutable minimumCap; // Minimum USDC needed for a successful sale
    uint256 public immutable maximumCap; // Maximum USDC deposit allowed (0 if none)

    // -----------------------------------------------------------------------
    // State Variables
    // -----------------------------------------------------------------------
    bool public finalized; // Whether sale has been finalized
    bool public successful; // Whether sale is successful
    uint256 public totalDeposited; // Total USDC deposited by all participants

    // user => total USDC deposited
    mapping(address => uint256) public deposits;

    // Merkle root for final token allocations (off-chain computed)
    bytes32 public merkleRoot;
    // Tracks whether a user has claimed their tokens
    mapping(address => bool) public hasClaimed;

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------
    /**
     * @param _treasury   The address to which proceeds will be sent after a successful sale
     * @param _usdcToken  The USDC token contract address
     * @param _startTime  The block timestamp when deposits can begin
     * @param _endTime    The block timestamp when deposits end
     * @param _minimumCap The minimum USDC deposit needed for the sale to succeed
     * @param _maximumCap The maximum USDC deposit allowed (use 0 if no max)
     */
    constructor(
        address _treasury,
        IERC20 _usdcToken,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _minimumCap,
        uint256 _maximumCap
    ) {
        require(_treasury != address(0), "treasury cannot be zero address");
        require(_endTime > _startTime, "endTime must be after startTime");

        treasury = _treasury;
        usdcToken = _usdcToken;
        startTime = _startTime;
        endTime = _endTime;
        minimumCap = _minimumCap;
        maximumCap = _maximumCap;
    }

    // -----------------------------------------------------------------------
    // Public (User) Functions
    // -----------------------------------------------------------------------

    /**
     * @notice Deposit USDC into the token sale. Must be within sale time window.
     * @param amount The amount of USDC to deposit
     */
    function deposit(uint256 amount) external nonReentrant {
        if (block.timestamp < startTime) revert SaleNotStarted();
        if (block.timestamp > endTime) revert SaleEnded();
        if (finalized) revert AlreadyFinalized();
        if (amount == 0) revert ZeroDeposit();

        // Transfer USDC from user to this contract
        bool successTransfer = usdcToken.transferFrom(msg.sender, address(this), amount);
        require(successTransfer, "USDC transfer failed");

        // Update state
        deposits[msg.sender] += amount;
        totalDeposited += amount;

        emit Deposit(msg.sender, amount);
    }

    /**
     * @notice Withdraw your USDC if the sale is not successful (i.e., below minimumCap).
     *         Callable after finalization if `successful == false`.
     */
    function withdraw() external nonReentrant {
        if (!finalized) revert NotFinalized();
        if (successful) revert SaleWasSuccessful();

        uint256 userDeposit = deposits[msg.sender];
        if (userDeposit == 0) revert NothingToWithdraw();

        // Zero out deposit before transferring
        deposits[msg.sender] = 0;

        bool successTransfer = usdcToken.transfer(msg.sender, userDeposit);
        require(successTransfer, "USDC transfer failed");

        emit Withdraw(msg.sender, userDeposit);
    }

    /**
     * @notice Claim your allocated tokens after the sale is finalized and successful.
     *         Requires a valid Merkle proof of (address, allocation).
     * @param allocation The total token amount allocated to msg.sender
     * @param proof      The Merkle proof for (msg.sender, allocation)
     */
    function claimTokens(uint256 allocation, bytes32[] calldata proof) external nonReentrant {
        if (!finalized || !successful) revert SaleNotSuccessful();
        if (merkleRoot == bytes32(0)) revert MerkleRootNotSet();
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();

        // Verify Merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, allocation));
        bool valid = MerkleProof.verify(proof, merkleRoot, leaf);
        if (!valid) revert InvalidProof();

        // Mark as claimed
        hasClaimed[msg.sender] = true;

        // --- Token Transfer Logic  ---
        saleToken.transfer(msg.sender, allocation);

        emit Claim(msg.sender, allocation);
    }

    // -----------------------------------------------------------------------
    // Owner Functions
    // -----------------------------------------------------------------------

    /**
     * @notice Finalize the sale after endTime (or earlier if max cap reached).
     *         Determines if it's successful and stops further deposits.
     */
    function finalize() external onlyOwner {
        if (finalized) revert AlreadyFinalized();

        if (block.timestamp < endTime && !(totalDeposited == maximumCap)) {
            revert SaleNotEnded();
        }

        finalized = true;
        successful = (totalDeposited >= minimumCap);

        emit Finalized(successful, totalDeposited);
    }

    /**
     * @notice Set the Merkle root that represents each user's final allocation.
     *         Can only be set after the sale is finalized and successful.
     * @param _merkleRoot The root of the Merkle tree
     */
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        if (!finalized || !successful) revert SaleNotSuccessful();
        merkleRoot = _merkleRoot;
        emit MerkleRootSet(_merkleRoot);
    }

    /**
     * @notice Withdraw the USDC proceeds to the treasury address (if sale is successful).
     *         Owner can call this at any time after successful finalization.
     */
    function withdrawProceeds() external onlyOwner {
        if (!finalized || !successful) revert SaleNotSuccessful();
        uint256 balance = usdcToken.balanceOf(address(this));
        bool successTransfer = usdcToken.transfer(treasury, balance);
        require(successTransfer, "USDC transfer failed");
    }
}

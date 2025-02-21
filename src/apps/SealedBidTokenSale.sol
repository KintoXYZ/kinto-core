// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {OwnableUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin-5.0.1/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
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
 *  - Early participation window for first 700 emissaries
 */
contract SealedBidTokenSale is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /* ============ Struct ============ */

    struct SaleInfo {
        /// @notice Timestamp when emissary early access begins
        uint256 preStartTime;
        /// @notice Timestamp when public sale begins
        uint256 startTime;
        /// @notice Minimum USDC required for sale success
        uint256 minimumCap;
        /// @notice Total USDC deposited by all users
        uint256 totalDeposited;
        /// @notice Total USDC withdrawn after failed sale
        uint256 totalWithdrawn;
        /// @notice Total USDC claimed by users
        uint256 totalUsdcClaimed;
        /// @notice Total sale tokens claimed
        uint256 totalSaleTokenClaimed;
        /// @notice Whether sale has been officially ended
        bool saleEnded;
        /// @notice Whether minimum cap was reached
        bool capReached;
        /// @notice Whether specified user has claimed tokens
        bool hasClaimed;
        /// @notice Total number of unique depositors
        uint256 contributorCount;
        /// @notice Current number of emissary participants
        uint256 currentEmissaryCount;
        /// @notice Deposit amount for specified user
        uint256 depositAmount;
        /// @notice Max price set by specified user
        uint256 maxPrice;
    }

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
    /// @notice Thrown when attempting withdrawals if cap is reached
    error CapReached();
    /// @notice Thrown when user has no funds to withdraw
    error NothingToWithdraw(address user);
    /// @notice Thrown when attempting to claim tokens more than once
    error AlreadyClaimed(address user);
    /// @notice Thrown when provided Merkle proof is invalid
    error InvalidProof(bytes32[] proof, bytes32 leaf);
    /// @notice Thrown when attempting claims before Merkle root is set
    error MerkleRootNotSet();
    /// @notice Thrown when attempting to deposit less than MIN_DEPOSIT
    error MinDeposit(uint256 amount);
    /// @notice Thrown when new max price is out of range
    error MaxPriceOutOfRange(uint256 amount);
    /// @notice Thrown when emissary slots are fully occupied
    error EmissaryFull();
    /// @notice Thrown when time configuration is invalid
    error InvalidTimeConfiguration();

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

    // Add this event to the SealedBidTokenSale contract's events section
    /// @notice Emitted when a user updates their max price
    /// @param user Address of the user updating their max price
    /// @param oldPrice Previous max price value
    /// @param newPrice New max price value
    event MaxPriceUpdated(address indexed user, uint256 oldPrice, uint256 newPrice);

    /* ============ Constant  ============ */

    /// @notice Token being sold in the sale
    uint256 public constant MIN_DEPOSIT = 250 * 1e6;
    /// @notice Maximum number of emissaries
    uint256 public constant MAX_EMISSARIES = 700;

    /* ============ Immutable ============ */

    /// @notice Token being sold in the sale
    IERC20 public immutable saleToken;
    /// @notice USDC token contract for deposits
    IERC20 public immutable USDC;
    /// @notice Address where sale proceeds will be sent
    address public immutable treasury;
    /// @notice Timestamp when emissary early access begins
    uint256 public immutable preStartTime;
    /// @notice Timestamp when the sale begins
    uint256 public immutable startTime;
    /// @notice Minimum amount of USDC required for sale success
    uint256 public immutable minimumCap;

    /* ============ State Variables ============ */

    /// @notice Whether the sale period has officially ended
    bool public saleEnded;
    /// @notice Whether the minimum cap was reached by end of sale
    bool public capReached;
    /// @notice Running total of USDC withdrawn from sale
    uint256 public totalWithdrawn;
    /// @notice Running total of USDC deposited into sale
    uint256 public totalDeposited;
    /// @notice Running total of USDC claimed from sale
    uint256 public totalUsdcClaimed;
    /// @notice Running total of sale token withdrawn from sale
    uint256 public totalSaleTokenClaimed;
    /// @notice Merkle root for verifying token allocations
    bytes32 public merkleRoot;
    /// @notice Maps user addresses to their USDC deposit amounts
    mapping(address => uint256) public deposits;
    /// @notice Maps user addresses to whether they've claimed tokens
    mapping(address => bool) public hasClaimed;
    /// @notice Maps user addresses to their selected maxPrice
    mapping(address => uint256) public maxPrices;
    /// @notice Count of all contributors
    uint256 public contributorCount;
    /// @notice Current number of emissary participants
    uint256 public currentEmissaryCount;
    /// @notice Maps user addresses to emissary status
    mapping(address => bool) public isEmissary;

    /* ============ Constructor ============ */
    /**
     * @notice Initializes the token sale with required parameters
     * @param _saleToken Address of the token being sold
     * @param _treasury Address where sale proceeds will be sent
     * @param _usdcToken Address of the USDC token contract
     * @param _startTime Timestamp when sale will begin
     * @param _minimumCap Minimum USDC amount required for sale success
     */
    constructor(
        address _saleToken,
        address _treasury,
        address _usdcToken,
        uint256 _preStartTime,
        uint256 _startTime,
        uint256 _minimumCap
    ) {
        _disableInitializers();

        if (_saleToken == address(0)) revert InvalidSaleTokenAddress(_saleToken);
        if (_treasury == address(0)) revert InvalidTreasuryAddress(_treasury);
        if (_preStartTime >= _startTime) revert InvalidTimeConfiguration();

        saleToken = IERC20(_saleToken);
        treasury = _treasury;
        USDC = IERC20(_usdcToken);
        preStartTime = _preStartTime;
        startTime = _startTime;
        minimumCap = _minimumCap;
    }

    /// @dev initialize the proxy
    function initialize() external virtual initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    /**
     * @dev Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the factory is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        (newImplementation);
    }

    /* ============ User Functions ============ */

    /**
     * @notice Allows users to deposit USDC into the token sale
     * @dev - Sale must be active (after start time, before end)
     *      - Amount must be greater than zero
     *      - Updates user's deposit balance, total deposits, and maxPrice
     *      - Transfers USDC from user to contract
     * @param amount Amount of USDC to deposit
     * @param maxPrice The maximum price set by the user for the token sale
     */
    function deposit(uint256 amount, uint256 maxPrice) external nonReentrant {
        if (saleEnded) revert SaleAlreadyEnded(block.timestamp);
        if (block.timestamp < preStartTime) revert SaleNotStarted(block.timestamp, preStartTime);
        if (amount < MIN_DEPOSIT) revert MinDeposit(amount);
        _checkMaxPrice(maxPrice);

        // Handle emissary period
        if (block.timestamp < startTime) {
            if (isEmissary[msg.sender] == false && currentEmissaryCount >= MAX_EMISSARIES) revert EmissaryFull();
            if (!isEmissary[msg.sender]) {
                isEmissary[msg.sender] = true;
                currentEmissaryCount++;
            }
        }

        deposits[msg.sender] += amount;
        totalDeposited += amount;
        contributorCount++;

        // Save the user's maxPrice
        maxPrices[msg.sender] = maxPrice;

        // Transfer USDC from user to contract
        USDC.safeTransferFrom(msg.sender, address(this), amount);

        // Emit deposit event
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
        // Verify sale has ended unsuccessfully
        if (!saleEnded) revert SaleNotEnded(block.timestamp);
        if (capReached) revert CapReached();

        // Get user's deposit amount
        uint256 amount = deposits[msg.sender];
        if (amount == 0) revert NothingToWithdraw(msg.sender);

        // Clear user's deposit before transfer
        deposits[msg.sender] = 0;
        totalWithdrawn += amount;

        // Return USDC to user
        USDC.safeTransfer(msg.sender, amount);

        // Emit withdrawal event
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
        // Verify sale ended successfully and claims are enabled
        if (!saleEnded || !capReached) revert CapNotReached();
        if (merkleRoot == bytes32(0)) revert MerkleRootNotSet();
        if (hasClaimed[user]) revert AlreadyClaimed(user);

        // Create and verify Merkle leaf
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(user, saleTokenAllocation, usdcAllocation))));
        if (!MerkleProof.verify(proof, merkleRoot, leaf)) revert InvalidProof(proof, leaf);

        // Mark as claimed before transfers
        hasClaimed[user] = true;

        // Transfer allocated sale tokens if any
        if (saleTokenAllocation > 0) {
            saleToken.safeTransfer(user, saleTokenAllocation);
            totalSaleTokenClaimed += saleTokenAllocation;
        }

        // Transfer allocated USDC if any
        if (usdcAllocation > 0) {
            USDC.safeTransfer(user, usdcAllocation);
            totalUsdcClaimed += usdcAllocation;
        }

        // Emit claim event
        emit Claimed(user, saleTokenAllocation);
    }

    /**
     * @notice Allows users to update their selected maxPrice for the token sale.
     * @param newMaxPrice The new maximum price value to be set for the user.
     */
    function updateMaxPrice(uint256 newMaxPrice) external nonReentrant {
        if (block.timestamp < preStartTime) revert SaleNotStarted(block.timestamp, preStartTime);
        if (saleEnded) revert SaleAlreadyEnded(block.timestamp);
        _checkMaxPrice(newMaxPrice);

        uint256 oldPrice = maxPrices[msg.sender];
        maxPrices[msg.sender] = newMaxPrice;
        emit MaxPriceUpdated(msg.sender, oldPrice, newMaxPrice);
    }

    function _checkMaxPrice(uint256 newMaxPrice) internal pure {
        if (newMaxPrice < 10 * 1e6 || newMaxPrice > 30 * 1e6) revert MaxPriceOutOfRange(newMaxPrice);
    }

    /* ============ Admin Functions ============ */

    /**
     * @notice Allows owner to officially end the sale
     * @dev - Can only be called once
     *      - Sets final sale status based on minimum cap
     *      - Emits event with final sale results
     */
    function endSale() external onlyOwner {
        // Verify sale hasn't already been ended
        if (saleEnded) revert SaleAlreadyEnded(block.timestamp);

        // Mark sale as ended and determine if cap was reached
        saleEnded = true;
        capReached = totalDeposited >= minimumCap;

        // Emit sale end event with final status
        emit SaleEnded(capReached, totalDeposited);
    }

    /**
     * @notice Sets the Merkle root for verifying token allocations
     * @dev - Sale must be ended successfully
     *      - Enables token claiming process
     * @param newRoot The Merkle root hash of all valid allocations
     */
    function setMerkleRoot(bytes32 newRoot) external onlyOwner {
        // Verify sale ended successfully before setting root
        if (!saleEnded || !capReached) revert CapNotReached();

        // Update Merkle root
        merkleRoot = newRoot;

        // Emit root update event
        emit MerkleRootSet(newRoot);
    }

    /**
     * @notice Allows owner to withdraw sale proceeds to treasury
     * @dev - Sale must be ended successfully
     *      - Transfers USDC to treasury address
     * @param amount The amount to move to the treasury
     */
    function withdrawProceeds(uint256 amount) external onlyOwner {
        // Verify sale ended successfully
        if (!saleEnded || !capReached) revert CapNotReached();

        // Transfer all USDC balance to treasury
        USDC.safeTransfer(treasury, amount);
    }

    /* ============ View Functions ============ */

    function saleStatus(address user) external view returns (SaleInfo memory) {
        return SaleInfo({
            preStartTime: preStartTime,
            startTime: startTime,
            minimumCap: minimumCap,
            totalDeposited: totalDeposited,
            totalWithdrawn: totalWithdrawn,
            totalUsdcClaimed: totalUsdcClaimed,
            totalSaleTokenClaimed: totalSaleTokenClaimed,
            saleEnded: saleEnded,
            capReached: capReached,
            hasClaimed: hasClaimed[user],
            contributorCount: contributorCount,
            currentEmissaryCount: currentEmissaryCount,
            depositAmount: deposits[user],
            maxPrice: maxPrices[user]
        });
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@aa/interfaces/IEntryPoint.sol";
import "@aa/core/EntryPoint.sol";
import "@kinto-core/interfaces/IKintoWallet.sol";
import "@kinto-core/wallet/KintoWallet.sol";
import "@kinto-core/libraries/ByteSignature.sol";

/**
 * @title MultisigSigner
 * @notice Contract for collecting and managing signatures for KintoWallet transactions
 * @dev Allows multiple signers to submit signatures which are then aggregated for execution
 */
contract MultisigSigner is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using ECDSAUpgradeable for bytes32;

    /// @notice The EntryPoint singleton contract used for submitting UserOperations
    IEntryPoint public immutable entryPoint;

    /// @dev Length of an ECDSA signature in bytes
    uint256 private constant SIGNATURE_LENGTH = 65;
    /// @dev Gas limit for the main call execution
    uint256 private constant CALL_GAS_LIMIT = 4_000_000;
    /// @dev Gas limit for the signature verification
    uint256 private constant VERIFICATION_GAS_LIMIT = 210_000;
    /// @dev Gas used before the verification starts
    uint256 private constant PRE_VERIFICATION_GAS = 21_000;
    /// @dev Default gas price used when submitting UserOperations
    uint256 private constant DEFAULT_GAS_PRICE = 1e9; // 1 Gwei

    /// @dev Wallet policy requiring only 1 signature
    uint8 private constant SINGLE_SIGNER = 1;
    /// @dev Wallet policy requiring all signatures except one
    uint8 private constant MINUS_ONE_SIGNER = 2;
    /// @dev Wallet policy requiring all signatures
    uint8 private constant ALL_SIGNERS = 3;
    /// @dev Wallet policy requiring exactly 2 signatures
    uint8 private constant TWO_SIGNERS = 4;

    /* ============ Custom Errors ============ */

    /// @dev Thrown when an operation is initiated by a non-owner of the wallet
    error NotWalletOwner(address wallet, address sender);
    /// @dev Thrown when an invalid wallet address is provided (e.g., zero address)
    error InvalidWalletAddress(address wallet);
    /// @dev Thrown when an invalid destination address is provided (e.g., zero address)
    error InvalidDestinationAddress(address destination);
    /// @dev Thrown when the calculated threshold is invalid for the given owner count
    error InvalidThreshold(uint256 threshold, uint256 ownerCount);
    /// @dev Thrown when attempting to access an operation that does not exist
    error OperationNotFound(bytes32 opId);
    /// @dev Thrown when attempting to modify or execute an already executed operation
    error OperationAlreadyExecuted(bytes32 opId);
    /// @dev Thrown when attempting to operate on an expired operation
    error OperationExpired(bytes32 opId, uint256 expiresAt, uint256 currentTime);
    /// @dev Thrown when a provided signature has an invalid length
    error InvalidSignatureLength(uint256 length, uint256 expected);
    /// @dev Thrown when a signature is from an address that is not a wallet owner
    error SignerNotWalletOwner(address wallet, address signer);
    /// @dev Thrown when a wallet owner attempts to sign an operation multiple times
    error DuplicateSignature(bytes32 opId, address signer);
    /// @dev Thrown when an operation doesn't have enough signatures to be executed
    error InsufficientSignatures(bytes32 opId, uint256 current, uint256 required);
    /// @dev Thrown when an unauthorized access is attempted
    error NotAuthorized();

    /// @dev Represents a multi-signature operation to be executed on a wallet
    struct Operation {
        /// @dev The KintoWallet address that will execute the transaction
        address wallet;
        /// @dev The target contract to call
        address destination;
        /// @dev ETH value to send with the call
        uint256 value;
        /// @dev Call data to be executed
        bytes data;
        /// @dev Nonce of the wallet for the UserOperation
        uint256 nonce;
        /// @dev Number of signatures needed based on wallet policy
        uint256 threshold;
        /// @dev Timestamp after which this operation expires
        uint256 expiresAt;
        /// @dev Whether the operation has been executed
        bool executed;
        /// @dev Tracking which owners have already signed
        mapping(address => bool) hasSigned;
        /// @dev Collected signatures (65 bytes each)
        bytes[] signatures;
    }

    /// @notice Maps operation IDs to their corresponding Operation data
    mapping(bytes32 => Operation) public operations;

    /* ============ Events ============ */

    /// @notice Emitted when a new operation is created
    /// @param opId Unique identifier for the operation
    /// @param wallet The KintoWallet address that will execute the transaction
    /// @param destination The target contract to call
    /// @param value ETH value to send with the call
    /// @param data Call data to be executed
    /// @param nonce Nonce of the wallet for the UserOperation
    /// @param threshold Number of signatures needed
    /// @param expiresAt Timestamp after which this operation expires
    event OperationCreated(
        bytes32 indexed opId,
        address indexed wallet,
        address destination,
        uint256 value,
        bytes data,
        uint256 nonce,
        uint256 threshold,
        uint256 expiresAt
    );

    /// @notice Emitted when a signature is added to an operation
    /// @param opId Unique identifier for the operation
    /// @param signer Address of the wallet owner who signed
    /// @param signature The ECDSA signature
    event SignatureAdded(bytes32 indexed opId, address indexed signer, bytes signature);

    /// @notice Emitted when an operation is executed
    /// @param opId Unique identifier for the operation
    /// @param wallet The KintoWallet address that executed the transaction
    /// @param destination The target contract called
    event OperationExecuted(bytes32 indexed opId, address indexed wallet, address indexed destination);

    /// @notice Emitted when an operation is cancelled
    /// @param opId Unique identifier for the cancelled operation
    event OperationCancelled(bytes32 indexed opId);

    /**
     * @custom:oz-upgrades-unsafe-allow constructor
     * @param _entryPoint The EntryPoint singleton contract
     */
    constructor(IEntryPoint _entryPoint) {
        entryPoint = _entryPoint;
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with an owner
     * @param initialOwner The address to set as the initial owner
     */
    function initialize(address initialOwner) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        _transferOwnership(initialOwner);
    }

    /**
     * @notice Creates a new operation for signature collection
     * @param wallet The KintoWallet address
     * @param destination The target contract to call
     * @param value ETH value to send
     * @param data Call data
     * @param expiresIn Time in seconds after which operation expires
     * @return opId Operation ID
     */
    function createOperation(address wallet, address destination, uint256 value, bytes calldata data, uint256 expiresIn)
        public
        returns (bytes32 opId)
    {
        // Verify that sender is an owner of the wallet
        if (!_isWalletOwner(wallet, msg.sender)) revert NotWalletOwner(wallet, msg.sender);
        if (wallet == address(0)) revert InvalidWalletAddress(wallet);
        if (destination == address(0)) revert InvalidDestinationAddress(destination);

        // Get owner count and wallet policy to determine the required threshold
        uint256 ownerCount = IKintoWallet(wallet).getOwnersCount();

        // Calculate threshold based on the wallet policy
        uint256 threshold = _calculateThreshold(IKintoWallet(wallet).signerPolicy(), ownerCount);
        if (threshold == 0 || threshold > ownerCount) revert InvalidThreshold(threshold, ownerCount);

        uint256 nonce = IKintoWallet(wallet).getNonce();
        uint256 expiresAt = block.timestamp + expiresIn;

        opId = keccak256(abi.encodePacked(wallet, destination, value, keccak256(data), nonce));

        Operation storage op = operations[opId];
        op.wallet = wallet;
        op.destination = destination;
        op.value = value;
        op.data = data;
        op.nonce = nonce;
        op.threshold = threshold;
        op.expiresAt = expiresAt;
        op.executed = false;

        emit OperationCreated(opId, wallet, destination, value, data, nonce, threshold, expiresAt);
        return opId;
    }

    /**
     * @notice Adds a signature to an operation
     * @param opId Operation ID
     * @param signature The ECDSA signature (65 bytes)
     */
    function addSignature(bytes32 opId, bytes calldata signature) external {
        // Verify that the operation exists
        Operation storage op = operations[opId];
        if (op.wallet == address(0)) revert OperationNotFound(opId);

        // Verify that sender is an owner of the wallet
        if (!_isWalletOwner(op.wallet, msg.sender)) revert NotWalletOwner(op.wallet, msg.sender);

        _addSignature(opId, signature);
    }

    /**
     * @notice Adds a signature to an operation and executes it if threshold is reached
     * @param opId Operation ID
     * @param signature The ECDSA signature (65 bytes)
     */
    function addSignatureAndExecute(bytes32 opId, bytes calldata signature) external {
        // Add the signature
        Operation storage op = operations[opId];
        if (op.wallet == address(0)) revert OperationNotFound(opId);

        // Verify that sender is an owner of the wallet
        if (!_isWalletOwner(op.wallet, msg.sender)) revert NotWalletOwner(op.wallet, msg.sender);

        _addSignature(opId, signature);

        // Check if we've reached the threshold
        if (op.signatures.length < op.threshold) {
            revert InsufficientSignatures(opId, op.signatures.length, op.threshold);
        }

        if (op.executed) revert OperationAlreadyExecuted(opId);
        if (block.timestamp > op.expiresAt) revert OperationExpired(opId, op.expiresAt, block.timestamp);

        // Mark as executed first to prevent reentrancy
        op.executed = true;

        // Combine signatures into a single byte array
        bytes memory combinedSignatures = new bytes(0);
        for (uint256 i = 0; i < op.signatures.length; i++) {
            combinedSignatures = abi.encodePacked(combinedSignatures, op.signatures[i]);
        }

        // Create and submit the UserOperation
        _executeUserOperation(op.wallet, op.destination, op.value, op.data, op.nonce, combinedSignatures);

        emit OperationExecuted(opId, op.wallet, op.destination);
    }

    /**
     * @notice Internal function to add a signature to an operation
     * @dev Verifies signature validity and prevents duplicates
     * @param opId Operation ID
     * @param signature The ECDSA signature (65 bytes)
     */
    function _addSignature(bytes32 opId, bytes calldata signature) internal {
        Operation storage op = operations[opId];

        // Validate operation state
        if (op.executed) revert OperationAlreadyExecuted(opId);
        if (block.timestamp > op.expiresAt) revert OperationExpired(opId, op.expiresAt, block.timestamp);
        if (signature.length != SIGNATURE_LENGTH) revert InvalidSignatureLength(signature.length, SIGNATURE_LENGTH);

        // Recover the signer from the signature
        bytes32 messageHash = _getOperationHash(op.wallet, op.destination, op.value, op.data, op.nonce);
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(signature);

        // Validate the signer
        if (!_isWalletOwner(op.wallet, signer)) revert SignerNotWalletOwner(op.wallet, signer);
        if (op.hasSigned[signer]) revert DuplicateSignature(opId, signer);

        // Record the signature
        op.hasSigned[signer] = true;
        op.signatures.push(signature);

        emit SignatureAdded(opId, signer, signature);
    }

    /**
     * @notice Executes an operation if threshold of signatures has been reached
     * @param opId Operation ID
     */
    function executeOperation(bytes32 opId) external {
        Operation storage op = operations[opId];

        if (op.wallet == address(0)) revert OperationNotFound(opId);
        if (op.executed) revert OperationAlreadyExecuted(opId);
        if (block.timestamp > op.expiresAt) revert OperationExpired(opId, op.expiresAt, block.timestamp);
        if (op.signatures.length < op.threshold) {
            revert InsufficientSignatures(opId, op.signatures.length, op.threshold);
        }

        // Mark as executed first to prevent reentrancy
        op.executed = true;

        // Combine signatures into a single byte array
        bytes memory combinedSignatures = new bytes(0);
        for (uint256 i = 0; i < op.signatures.length; i++) {
            combinedSignatures = abi.encodePacked(combinedSignatures, op.signatures[i]);
        }

        // Create and submit the UserOperation
        _executeUserOperation(op.wallet, op.destination, op.value, op.data, op.nonce, combinedSignatures);

        emit OperationExecuted(opId, op.wallet, op.destination);
    }

    /**
     * @notice Cancels an operation that hasn't been executed yet
     * @param opId Operation ID
     */
    function cancelOperation(bytes32 opId) external onlyOwner {
        Operation storage op = operations[opId];

        if (op.wallet == address(0)) revert OperationNotFound(opId);
        if (op.executed) revert OperationAlreadyExecuted(opId);

        delete operations[opId];

        emit OperationCancelled(opId);
    }

    /**
     * @notice Authorizes an upgrade to a new implementation
     * @dev Required by the UUPSUpgradeable contract
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Creates and submits a UserOperation to the EntryPoint
     * @dev Private function to handle the actual execution via Account Abstraction
     * @param wallet The KintoWallet address that will execute the transaction
     * @param destination The target contract to call
     * @param value ETH value to send with the call
     * @param data Call data to be executed
     * @param nonce Nonce of the wallet for the UserOperation
     * @param signatures Combined signatures from wallet owners
     */
    function _executeUserOperation(
        address wallet,
        address destination,
        uint256 value,
        bytes memory data,
        uint256 nonce,
        bytes memory signatures
    ) private {
        // Prepare the calldata for the wallet's execute function
        bytes memory callData = abi.encodeCall(KintoWallet.execute, (destination, value, data));

        // Create the UserOperation
        UserOperation memory userOp = UserOperation({
            sender: wallet,
            nonce: nonce,
            initCode: bytes(""),
            callData: callData,
            callGasLimit: CALL_GAS_LIMIT,
            verificationGasLimit: VERIFICATION_GAS_LIMIT,
            preVerificationGas: PRE_VERIFICATION_GAS,
            maxFeePerGas: DEFAULT_GAS_PRICE,
            maxPriorityFeePerGas: DEFAULT_GAS_PRICE,
            paymasterAndData: bytes(""),
            signature: signatures
        });

        // Create array for EntryPoint.handleOps
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // Submit the operation
        entryPoint.handleOps(userOps, payable(msg.sender));
    }

    /**
     * @notice Gets the operation hash that needs to be signed
     * @dev Computes the hash following EIP-4337 UserOperation hash calculation
     * @param wallet The KintoWallet address that will execute the transaction
     * @param destination The target contract to call
     * @param value ETH value to send with the call
     * @param data Call data to be executed
     * @param nonce Nonce of the wallet for the UserOperation
     * @return The hash that should be signed by wallet owners
     */
    function _getOperationHash(address wallet, address destination, uint256 value, bytes memory data, uint256 nonce)
        private
        view
        returns (bytes32)
    {
        // Prepare the calldata for the wallet's execute function
        bytes memory callData = abi.encodeCall(KintoWallet.execute, (destination, value, data));

        // Create the UserOperation (partial, for hashing)
        UserOperation memory userOp = UserOperation({
            sender: wallet,
            nonce: nonce,
            initCode: bytes(""),
            callData: callData,
            callGasLimit: CALL_GAS_LIMIT,
            verificationGasLimit: VERIFICATION_GAS_LIMIT,
            preVerificationGas: PRE_VERIFICATION_GAS,
            maxFeePerGas: DEFAULT_GAS_PRICE,
            maxPriorityFeePerGas: DEFAULT_GAS_PRICE,
            paymasterAndData: bytes(""),
            signature: bytes("")
        });

        // Hash using the same algorithm as in the UserOp contract
        bytes32 opHash = keccak256(
            abi.encode(
                userOp.sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.callGasLimit,
                userOp.verificationGasLimit,
                userOp.preVerificationGas,
                userOp.maxFeePerGas,
                userOp.maxPriorityFeePerGas,
                keccak256(userOp.paymasterAndData)
            )
        );

        // Add chain-specific data to the hash
        return keccak256(abi.encode(opHash, address(entryPoint), block.chainid));
    }

    /**
     * @notice Calculates the signature threshold based on wallet policy
     * @dev Converts a wallet's signer policy code to a concrete threshold value
     * @param policy The wallet's signer policy (1=Single, 2=All-but-one, 3=All, 4=Two)
     * @param ownerCount The number of wallet owners
     * @return threshold The number of signatures required
     */
    function _calculateThreshold(uint8 policy, uint256 ownerCount) internal pure returns (uint256) {
        if (policy == SINGLE_SIGNER) {
            return 1;
        } else if (policy == TWO_SIGNERS) {
            return 2;
        } else if (policy == MINUS_ONE_SIGNER) {
            return ownerCount > 0 ? ownerCount - 1 : 0;
        } else if (policy == ALL_SIGNERS) {
            return ownerCount;
        }

        // Default fallback (should not happen with valid policy)
        return 0;
    }

    /**
     * @notice Checks if an address is an owner of a wallet
     * @dev Iterates through the wallet's owner list to find a match
     * @param wallet The wallet address to check
     * @param owner The potential owner address to verify
     * @return True if the address is an owner of the wallet
     */
    function _isWalletOwner(address wallet, address owner) internal view returns (bool) {
        address[] memory owners = IKintoWallet(wallet).getOwners();
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == owner) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Gets operation details
     * @param opId Operation ID
     * @return wallet Target wallet
     * @return destination Destination address
     * @return value ETH value
     * @return data Call data
     * @return nonce Wallet nonce
     * @return threshold Required signatures
     * @return expiresAt Expiration timestamp
     * @return executed Whether executed
     * @return signatureCount Number of signatures collected
     */
    function getOperation(bytes32 opId)
        external
        view
        returns (
            address wallet,
            address destination,
            uint256 value,
            bytes memory data,
            uint256 nonce,
            uint256 threshold,
            uint256 expiresAt,
            bool executed,
            uint256 signatureCount
        )
    {
        Operation storage op = operations[opId];

        return (
            op.wallet,
            op.destination,
            op.value,
            op.data,
            op.nonce,
            op.threshold,
            op.expiresAt,
            op.executed,
            op.signatures.length
        );
    }

    /**
     * @notice Checks if an operation can be executed
     * @param opId Operation ID
     * @return True if the operation can be executed
     */
    function canExecute(bytes32 opId) external view returns (bool) {
        Operation storage op = operations[opId];

        return (
            op.wallet != address(0) && !op.executed && block.timestamp <= op.expiresAt
                && op.signatures.length >= op.threshold
        );
    }

    /**
     * @notice Gets the operation hash for a specific operation
     * @param opId Operation ID
     * @return The hash that should be signed by wallet owners
     */
    function getOperationHash(bytes32 opId) external view returns (bytes32) {
        Operation storage op = operations[opId];
        if (op.wallet == address(0)) revert OperationNotFound(opId);

        return _getOperationHash(op.wallet, op.destination, op.value, op.data, op.nonce);
    }
}

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

    // The EntryPoint singleton
    IEntryPoint public immutable entryPoint;

    // Constants
    uint256 private constant SIGNATURE_LENGTH = 65;
    uint256 private constant CALL_GAS_LIMIT = 4_000_000;
    uint256 private constant VERIFICATION_GAS_LIMIT = 210_000;
    uint256 private constant PRE_VERIFICATION_GAS = 21_000;
    uint256 private constant DEFAULT_GAS_PRICE = 1e9; // 1 Gwei

    // Wallet signer policy constants
    uint8 private constant SINGLE_SIGNER = 1;
    uint8 private constant MINUS_ONE_SIGNER = 2;
    uint8 private constant ALL_SIGNERS = 3;
    uint8 private constant TWO_SIGNERS = 4;

    /* ============ Custom Errors ============ */

    error NotWalletOwner(address wallet, address sender);
    error InvalidWalletAddress(address wallet);
    error InvalidDestinationAddress(address destination);
    error InvalidThreshold(uint256 threshold, uint256 ownerCount);
    error OperationNotFound(bytes32 opId);
    error OperationAlreadyExecuted(bytes32 opId);
    error OperationExpired(bytes32 opId, uint256 expiresAt, uint256 currentTime);
    error InvalidSignatureLength(uint256 length, uint256 expected);
    error SignerNotWalletOwner(address wallet, address signer);
    error DuplicateSignature(bytes32 opId, address signer);
    error InsufficientSignatures(bytes32 opId, uint256 current, uint256 required);
    error NotAuthorized();

    struct Operation {
        address wallet; // The KintoWallet address
        address destination; // The target contract to call
        uint256 value; // ETH value to send
        bytes data; // Call data
        uint256 nonce; // Nonce of the wallet
        uint256 threshold; // Number of signatures needed
        uint256 expiresAt; // Expiration timestamp
        bool executed; // Whether operation has been executed
        mapping(address => bool) hasSigned; // Tracking which signers have signed
        bytes[] signatures; // Collected signatures (65 bytes each)
    }

    // Operation ID => Operation
    mapping(bytes32 => Operation) public operations;

    // Events
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

    event SignatureAdded(bytes32 indexed opId, address indexed signer, bytes signature);
    event OperationExecuted(bytes32 indexed opId, address indexed wallet, address indexed destination);
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
     * @notice Internal function to add a signature
     * @param opId Operation ID
     * @param signature The ECDSA signature (65 bytes)
     */
    function _addSignature(bytes32 opId, bytes calldata signature) internal {
        Operation storage op = operations[opId];

        if (op.executed) revert OperationAlreadyExecuted(opId);
        if (block.timestamp > op.expiresAt) revert OperationExpired(opId, op.expiresAt, block.timestamp);
        if (signature.length != SIGNATURE_LENGTH) revert InvalidSignatureLength(signature.length, SIGNATURE_LENGTH);

        // Get the operation hash
        bytes32 messageHash = _getOperationHash(op.wallet, op.destination, op.value, op.data, op.nonce);
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(signature);

        // Verify that signer is an owner of the wallet
        if (!_isWalletOwner(op.wallet, signer)) revert SignerNotWalletOwner(op.wallet, signer);
        if (op.hasSigned[signer]) revert DuplicateSignature(opId, signer);

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
     * @dev Private function to handle the actual execution
     */
    function _executeUserOperation(
        address wallet,
        address destination,
        uint256 value,
        bytes memory data,
        uint256 nonce,
        bytes memory signatures
    ) private {
        // Use the immutable EntryPoint reference

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
     * @return The hash that should be signed by wallet owners
     */
    function _getOperationHash(address wallet, address destination, uint256 value, bytes memory data, uint256 nonce)
        private
        view
        returns (bytes32)
    {
        // Use the immutable EntryPoint

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

        return keccak256(abi.encode(opHash, address(entryPoint), block.chainid));
    }

    /**
     * @notice Calculates the signature threshold based on wallet policy
     * @param policy The wallet's signer policy
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
     * @param wallet The wallet address
     * @param owner The potential owner address
     * @return True if the address is an owner
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {BasePaymaster} from "@aa-v7/core/BasePaymaster.sol";
import {UserOperationLib} from "@aa-v7/core/UserOperationLib.sol";
import {_packValidationData} from "@aa-v7/core/Helpers.sol";
import {PackedUserOperation} from "@aa-v7/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "@aa-v7/interfaces/IEntryPoint.sol";

import "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import "@openzeppelin-5.0.1/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin-5.0.1/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @notice
 * A signature paymaster that uses external service to decide whether to pay for the UserOp.
 * The paymaster trusts an external signer to sign the transaction.
 * The calling user must pass the UserOp to that external signer first, which performs
 * whatever off-chain verification before signing the UserOp.
 * Note that this signature is NOT a replacement for the account-specific signature:
 * - the paymaster checks a signature to agree to PAY for GAS.
 * - the account checks a signature to prove identity and account ownership.
 */
contract SignaturePaymaster is BasePaymaster, Initializable, UUPSUpgradeable {
    using UserOperationLib for PackedUserOperation;
    using ECDSA for bytes32;

    address public immutable verifyingSigner;

    uint256 private constant VALID_TIMESTAMP_OFFSET = 20;
    uint256 private constant SIGNATURE_OFFSET = 84;

    mapping(address => uint256) public senderNonce;

    // ========== Constructor & Upgrades ============

    constructor(IEntryPoint _entryPoint, address _verifyingSigner) BasePaymaster(_entryPoint) {
        _disableInitializers();
        verifyingSigner = _verifyingSigner;
    }

    /**
     * @dev The _entryPoint member is immutable, to reduce gas consumption.  To upgrade EntryPoint,
     * a new implementation of SignaturePaymaster must be deployed with the new EntryPoint address.
     */
    function initialize(address owner) external virtual initializer {
        __UUPSUpgradeable_init();
        _transferOwnership(owner);
    }

    /**
     * @dev Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the implementation is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override {
        require(msg.sender == owner(), "VP: not owner");
        (newImplementation);
    }

    /* =============== Viewers & Validation ============= */

    /**
     * return the hash we're going to sign off-chain (and validate on-chain)
     * this method is called by the off-chain service, to sign the request.
     * it is called on-chain from the validatePaymasterUserOp, to validate the signature.
     * note that this signature covers all fields of the UserOperation, except the "paymasterAndData",
     * which will carry the signature itself.
     */
    function getHash(PackedUserOperation calldata userOp, uint48 validUntil, uint48 validAfter)
        public
        view
        returns (bytes32)
    {
        //can't use userOp.hash(), since it contains also the paymasterAndData itself.
        address sender = userOp.getSender();
        return keccak256(
            abi.encode(
                sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.accountGasLimits,
                uint256(bytes32(userOp.paymasterAndData[PAYMASTER_VALIDATION_GAS_OFFSET:PAYMASTER_DATA_OFFSET])),
                userOp.preVerificationGas,
                userOp.gasFees,
                block.chainid,
                address(this),
                validUntil,
                validAfter
            )
        );
    }

    /**
     * verify our external signer signed this request.
     * the "paymasterAndData" is expected to be the paymaster and a signature over the entire request params
     * paymasterAndData[:20] : address(this)
     * paymasterAndData[20:84] : abi.encode(validUntil, validAfter)
     * paymasterAndData[84:] : signature
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32, /*userOpHash*/
        uint256 requiredPreFund
    ) internal view override returns (bytes memory context, uint256 validationData) {
        (requiredPreFund);

        (uint48 validUntil, uint48 validAfter, bytes calldata signature) =
            parsePaymasterAndData(userOp.paymasterAndData);
        //ECDSA library supports both 64 and 65-byte long signatures.
        // we only "require" it here so that the revert reason on invalid signature will be of "VerifyingPaymaster", and not "ECDSA"
        require(
            signature.length == 64 || signature.length == 65,
            "VerifyingPaymaster: invalid signature length in paymasterAndData"
        );
        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(getHash(userOp, validUntil, validAfter));

        //don't revert on signature failure: return SIG_VALIDATION_FAILED
        if (verifyingSigner != ECDSA.recover(hash, signature)) {
            return ("", _packValidationData(true, validUntil, validAfter));
        }

        //no need for other on-chain validation: entire UserOp should have been checked
        // by the external service prior to signing it.
        return ("", _packValidationData(false, validUntil, validAfter));
    }

    function parsePaymasterAndData(bytes calldata paymasterAndData)
        public
        pure
        returns (uint48 validUntil, uint48 validAfter, bytes calldata signature)
    {
        (validUntil, validAfter) = abi.decode(paymasterAndData[VALID_TIMESTAMP_OFFSET:], (uint48, uint48));
        signature = paymasterAndData[SIGNATURE_OFFSET:];
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {LibString} from "solady/utils/LibString.sol";

import "@aa/interfaces/IEntryPoint.sol";
import "@aa/core/EntryPoint.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "@kinto-core/wallet/KintoWallet.sol";
import "@kinto-core/wallet/KintoWalletFactory.sol";
import "@kinto-core-test/helpers/SignerHelper.sol";

import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import {Script} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

abstract contract UserOp is Test, SignerHelper {
    using ECDSAUpgradeable for bytes32;
    using LibString for *;

    uint256 constant SECP256K1_MAX_PRIVATE_KEY = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    // block's gas limit is 32mil, so main call 30mil
    uint256 constant CALL_GAS_LIMIT = 4_000_000;
    uint256 constant VERIFICATION_GAS_LIMIT = 210_000;
    uint256 constant PRE_VERIFICATION_GAS = 21_000;
    // MAX_FEE_PER_GAS and MAX_PRIORITY_FEE_PER_GAS are both set to 1gwei
    // which force EIP4337 to work in legacy mode
    uint256 constant MAX_FEE_PER_GAS = 1;
    uint256 constant MAX_PRIORITY_FEE_PER_GAS = 1e9;

    struct OperationParamsBatch {
        address[] targets;
        uint256[] values;
        bytes[] bytesOps;
    }

    /**
     * @notice Creates a UserOperation with all parameters including chainID, paymaster, gas limits, and batch operations.
     * @param chainID The chain ID for the operation.
     * @param from The sender address.
     * @param target The target address for the call.
     * @param value The value to send with the call.
     * @param nonce The nonce for the operation.
     * @param privateKeyOwners Array of private keys for signing the operation.
     * @param bytesOp The call data for the operation.
     * @param paymaster The paymaster address.
     * @param gasLimits Array of gas limits [callGasLimit, maxFeePerGas, maxPriorityFeePerGas].
     * @param isBatch Boolean indicating if the operation is a batch operation.
     * @param opParams The parameters for batch operations.
     * @return op The created UserOperation.
     */
    function _createUserOperation(
        uint256 chainID,
        address from,
        address target,
        uint256 value,
        uint256 nonce,
        uint256[] memory privateKeyOwners,
        bytes memory bytesOp,
        address paymaster,
        uint256[3] memory gasLimits,
        bool isBatch,
        OperationParamsBatch memory opParams
    ) internal returns (UserOperation memory op) {
        bytes memory callData;
        if (isBatch) {
            callData = abi.encodeCall(KintoWallet.executeBatch, (opParams.targets, opParams.values, opParams.bytesOps));
        } else {
            callData = abi.encodeCall(KintoWallet.execute, (target, value, bytesOp));
        }

        op = UserOperation({
            sender: from,
            nonce: nonce,
            initCode: bytes(""),
            callData: callData,
            callGasLimit: gasLimits[0], // generate from call simulation
            verificationGasLimit: 210_000, // verification gas. will add create2 cost (3200+200*length) if initCode exists
            preVerificationGas: 21_000, // should also cover calldata cost.
            maxFeePerGas: gasLimits[1], // grab from current gas
            maxPriorityFeePerGas: gasLimits[2], // grab from current gas
            paymasterAndData: abi.encodePacked(paymaster),
            signature: bytes("")
        });
        op.signature = _signUserOp(op, KintoWallet(payable(from)).entryPoint(), chainID, privateKeyOwners);
        return op;
    }

    /**
     * @notice Creates a UserOperation without specifying paymaster, gas limits, or batch operations.
     */
    function _createUserOperation(
        address from,
        address target,
        uint256 nonce,
        uint256[] memory privateKeyOwners,
        bytes memory bytesOp
    ) internal returns (UserOperation memory op) {
        return _createUserOperation(
            block.chainid,
            from,
            target,
            0,
            nonce,
            privateKeyOwners,
            bytesOp,
            address(0),
            [CALL_GAS_LIMIT, MAX_FEE_PER_GAS, MAX_PRIORITY_FEE_PER_GAS],
            false,
            OperationParamsBatch(new address[](0), new uint256[](0), new bytes[](0))
        );
    }

    /**
     * @notice Creates a UserOperation with a specified paymaster but without gas limits or batch operations.
     */
    function _createUserOperation(
        address from,
        address target,
        uint256 nonce,
        uint256[] memory privateKeyOwners,
        bytes memory bytesOp,
        address paymaster
    ) internal returns (UserOperation memory op) {
        return _createUserOperation(
            block.chainid,
            from,
            target,
            0,
            nonce,
            privateKeyOwners,
            bytesOp,
            paymaster,
            [CALL_GAS_LIMIT, MAX_FEE_PER_GAS, MAX_PRIORITY_FEE_PER_GAS],
            false,
            OperationParamsBatch(new address[](0), new uint256[](0), new bytes[](0))
        );
    }

    /**
     * @notice Creates a UserOperation with specified chainID and paymaster but without batch operations.
     * @param chainID The chain ID for the operation.
     * @param from The sender address.
     * @param target The target address for the call.
     * @param value The value to send with the call.
     * @param nonce The nonce for the operation.
     * @param privateKeyOwners Array of private keys for signing the operation.
     * @param bytesOp The call data for the operation.
     * @param paymaster The paymaster address.
     * @return op The created UserOperation.
     */
    function _createUserOperation(
        uint256 chainID,
        address from,
        address target,
        uint256 value,
        uint256 nonce,
        uint256[] memory privateKeyOwners,
        bytes memory bytesOp,
        address paymaster
    ) internal returns (UserOperation memory op) {
        return _createUserOperation(
            chainID,
            from,
            target,
            value,
            nonce,
            privateKeyOwners,
            bytesOp,
            paymaster,
            [CALL_GAS_LIMIT, MAX_FEE_PER_GAS, MAX_PRIORITY_FEE_PER_GAS],
            false,
            OperationParamsBatch(new address[](0), new uint256[](0), new bytes[](0))
        );
    }

    /**
     * @notice Creates a UserOperation for batch execution with a specified paymaster.
     */
    function _createUserOperation(
        address from,
        uint256 nonce,
        uint256[] memory privateKeyOwners,
        OperationParamsBatch memory opParams,
        address paymaster
    ) internal returns (UserOperation memory op) {
        return _createUserOperation(
            block.chainid,
            from,
            address(0),
            0,
            nonce,
            privateKeyOwners,
            bytes(""),
            paymaster,
            [CALL_GAS_LIMIT, MAX_FEE_PER_GAS, MAX_PRIORITY_FEE_PER_GAS],
            true,
            opParams
        );
    }

    // signature helpers

    function _packUserOp(UserOperation memory op, bool forSig) internal pure returns (bytes memory) {
        if (forSig) {
            return abi.encode(
                op.sender,
                op.nonce,
                keccak256(op.initCode),
                keccak256(op.callData),
                op.callGasLimit,
                op.verificationGasLimit,
                op.preVerificationGas,
                op.maxFeePerGas,
                op.maxPriorityFeePerGas,
                keccak256(op.paymasterAndData)
            );
        }
        return abi.encode(
            op.sender,
            op.nonce,
            op.initCode,
            op.callData,
            op.callGasLimit,
            op.verificationGasLimit,
            op.preVerificationGas,
            op.maxFeePerGas,
            op.maxPriorityFeePerGas,
            op.paymasterAndData,
            op.signature
        );
    }

    function _getUserOpHash(UserOperation memory op, IEntryPoint _entryPoint, uint256 chainID)
        internal
        pure
        returns (bytes32)
    {
        bytes32 opHash = keccak256(_packUserOp(op, true));
        return keccak256(abi.encode(opHash, address(_entryPoint), chainID));
    }

    function _signUserOp(
        UserOperation memory op,
        IEntryPoint _entryPoint,
        uint256 chainID,
        uint256[] memory privateKeys
    ) internal returns (bytes memory) {
        bytes32 hash = _getUserOpHash(op, _entryPoint, chainID);
        hash = hash.toEthSignedMessageHash();

        bytes memory signature;
        for (uint256 i = 0; i < privateKeys.length; i++) {
            // if privKey == 0 | 1, it means we need to sign with Ledger | Trezor
            if (privateKeys[i] == 0 || privateKeys[i] == 1) {
                bytes memory newSig = signWithHW(privateKeys[i], _getUserOpHash(op, _entryPoint, chainID));
                signature = abi.encodePacked(signature, newSig);
            } else {
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKeys[i], hash);
                if (i == 0) {
                    signature = abi.encodePacked(r, s, v);
                } else {
                    signature = abi.encodePacked(signature, r, s, v);
                }
            }
        }
        return signature;
    }
}

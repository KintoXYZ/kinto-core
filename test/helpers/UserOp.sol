// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {LibString} from "solady/utils/LibString.sol";

import "@aa/interfaces/IEntryPoint.sol";
import "@aa/core/EntryPoint.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "@kinto-core/wallet/KintoWallet.sol";
import "@kinto-core/wallet/KintoWalletFactory.sol";

abstract contract UserOp is Test {
    using ECDSAUpgradeable for bytes32;
    using LibString for *;

    uint256 constant SECP256K1_MAX_PRIVATE_KEY = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    // gas constants
    uint256 constant CALL_GAS_LIMIT = 4_000_000;
    uint256 constant VERIFICATION_GAS_LIMIT = 210_000;
    uint256 constant PRE_VERIFICATION_GAS = 21_000;
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
    ) internal view returns (UserOperation memory op) {
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
    ) internal view returns (UserOperation memory op) {
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
    ) internal view returns (UserOperation memory op) {
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
    ) internal view returns (UserOperation memory op) {
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
    ) internal view returns (UserOperation memory op) {
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

    ////////// VERSION 2//////////
    /**
     * @notice Creates a UserOperation with all parameters including chainID, paymaster, gas limits, and batch operations.
     * @param chainID The chain ID for the operation.
     * @param from The sender address.
     * @param target The target address for the call.
     * @param value The value to send with the call.
     * @param nonce The nonce for the operation.
     * @param bytesOp The call data for the operation.
     * @param paymaster The paymaster address.
     * @param gasLimits Array of gas limits [callGasLimit, maxFeePerGas, maxPriorityFeePerGas].
     * @param isBatch Boolean indicating if the operation is a batch operation.
     * @param opParams The parameters for batch operations.
     * @return op The created UserOperation.
     */
    function _createUserOperation2(
        uint256 chainID,
        address from,
        address target,
        uint256 value,
        uint256 nonce,
        bytes memory bytesOp,
        address paymaster,
        uint256[3] memory gasLimits,
        bool isBatch,
        OperationParamsBatch memory opParams
    ) internal view returns (UserOperation memory op) {
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
        return op;
    }

    /**
     * @notice Creates a UserOperation without specifying paymaster, gas limits, or batch operations.
     */
    function _createUserOperation2(
        address from,
        address target,
        uint256 nonce,
        uint256[] memory privateKeyOwners,
        bytes memory bytesOp
    ) internal view returns (UserOperation memory op) {
        return _createUserOperation2(
            block.chainid,
            from,
            target,
            0,
            nonce,
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
    function _createUserOperation2(
        address from,
        address target,
        uint256 nonce,
        uint256[] memory privateKeyOwners,
        bytes memory bytesOp,
        address paymaster
    ) internal view returns (UserOperation memory op) {
        return _createUserOperation2(
            block.chainid,
            from,
            target,
            0,
            nonce,
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
     * @param bytesOp The call data for the operation.
     * @param paymaster The paymaster address.
     * @return op The created UserOperation.
     */
    function _createUserOperation2(
        uint256 chainID,
        address from,
        address target,
        uint256 value,
        uint256 nonce,
        bytes memory bytesOp,
        address paymaster
    ) internal view returns (UserOperation memory op) {
        return _createUserOperation2(
            chainID,
            from,
            target,
            value,
            nonce,
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
    function _createUserOperation2(address from, uint256 nonce, OperationParamsBatch memory opParams, address paymaster)
        internal
        view
        returns (UserOperation memory op)
    {
        return _createUserOperation2(
            block.chainid,
            from,
            address(0),
            0,
            nonce,
            bytes(""),
            paymaster,
            [CALL_GAS_LIMIT, MAX_FEE_PER_GAS, MAX_PRIORITY_FEE_PER_GAS],
            true,
            opParams
        );
    }
    ///////////////////////////

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

    function _signUserOp(UserOperation memory op, IEntryPoint _entryPoint, uint256 chainID, uint256 privateKey)
        internal
        pure
        returns (bytes memory)
    {
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = privateKey;
        return _signUserOp(op, _entryPoint, chainID, privateKeys);
    }

    function _signUserOpWithHW(string memory hwType, UserOperation memory op, IEntryPoint _entryPoint, uint256 chainID)
        internal
        returns (bytes memory signature)
    {
        bytes32 hash = _getUserOpHash(op, _entryPoint, chainID);
        hash = hash.toEthSignedMessageHash();

        string[] memory args = new string[](5);
        args[0] = "cast";
        args[1] = "wallet";
        args[2] = "sign";
        args[3] = string(abi.encodePacked(hash));
        if (hwType.eqs("ledger")) {
            args[4] = "--ledger";
            args[5] = "--no-hash";
        } else if (hwType.eqs("trezor")) {
            args[4] = "--trezor";
        }
        signature = bytes(vm.ffi(args));
    }

    function _signUserOp(
        UserOperation memory op,
        IEntryPoint _entryPoint,
        uint256 chainID,
        uint256[] memory privateKeys
    ) internal pure returns (bytes memory) {
        bytes32 hash = _getUserOpHash(op, _entryPoint, chainID);
        hash = hash.toEthSignedMessageHash();

        bytes memory signature;
        for (uint256 i = 0; i < privateKeys.length; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKeys[i], hash);
            if (i == 0) {
                signature = abi.encodePacked(r, s, v);
            } else {
                signature = abi.encodePacked(signature, r, s, v);
            }
        }

        return signature;
    }

    function _mergeSignatures(bytes[] memory signatures) internal pure returns (bytes memory mergedSignatures) {
        require(signatures.length > 0, "No signatures to merge");

        uint256 totalLength = signatures.length * 65;
        mergedSignatures = new bytes(totalLength);

        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory signature = signatures[i];
            require(signature.length == 65, "Invalid signature length");

            uint256 offset = i * 65;
            for (uint256 j = 0; j < 65; j++) {
                mergedSignatures[offset + j] = signature[j];
            }
        }
    }
}

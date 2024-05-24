// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {LibString} from "solady/utils/LibString.sol";

import "@aa/interfaces/IEntryPoint.sol";
import "@aa/core/EntryPoint.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "@kinto-core/wallet/KintoWallet.sol";
import "@kinto-core/wallet/KintoWalletFactory.sol";

import "forge-std/Vm.sol";
import "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

abstract contract UserOp is Test {
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

    function _signUserOp(UserOperation memory op, IEntryPoint _entryPoint, uint256 chainID, uint256 privateKey)
        internal
        returns (bytes memory)
    {
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = privateKey;
        return _signUserOp(op, _entryPoint, chainID, privateKeys);
    }

    function _signUserOpWithHW(uint256 hwType, UserOperation memory op, IEntryPoint _entryPoint, uint256 chainID)
        internal
        returns (bytes memory signature)
    {

        // Option 1
        bytes32 hash = _getUserOpHash(op, _entryPoint, chainID);
        hash = hash.toEthSignedMessageHash();
        string memory hashString = toHexString(hash.toEthSignedMessageHash());
        console.log("\nMessage hash:");
        console.logBytes32(hash);
        console.log("\nMessage hash with Ethereum prefix:");
        console.logBytes32(hash.toEthSignedMessageHash());
        console.log("\nMessage hash with Ethereum prefix converted to hash string:");
        console.log(hashString);

        console.log("\nSigning hash string...");
        string memory commandStart = "cast wallet sign ";
        string memory flags;
        if (hwType == 0) {
            flags = string.concat("--ledger ");
        } else if (hwType == 1) {
            flags = string.concat("--trezor ");
        }

        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = string.concat(commandStart, flags, hashString);
        signature = bytes(vm.ffi(inputs));
        console.log("\nSignature:");
        console.logBytes(signature);

        // Option 2
        // string[] memory args = new string[](5);
        // args[0] = "cast";
        // args[1] = "wallet";
        // args[2] = "sign";
        // args[3] = hashString;
        // if (hwType == 0) {
        //     args[4] = "--ledger";
        // } else if (hwType == 1) {
        //     args[4] = "--trezor";
        // }
        // signature = bytes(vm.ffi(args));
        if (hwType == 1) {
            signature = _fixSignature(signature);
        }

        // PROBLEM:
        // Seems like the signer returned is not the same as the one that signed the message.
        // If I verify the signature with the hashString on cast, it works fine.
        // Somehow, the hashString and the hash.toEthSignedMessageHash() are not the same thing
        // for the signature creation.
        (address signer, ) = ECDSAUpgradeable.tryRecover(hash.toEthSignedMessageHash(), signature);
        console.log("\nHW Signer is: %s", signer);
    }

    function toHexString(bytes32 data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            str[i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
            str[1 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }

    // Change `r` (recovery) value to 1B (27) or 1C (28) for Trezor signatures
    // `r` value is the last byte of the signature
    // @dev we need to remove the last byte of the signature and add 1B (27) or 1C (28),
    // seems like this is what most wallets do to sign messages.
    function _fixSignature(bytes memory signature) internal view returns (bytes memory) {
        console.log("\nFixing Trezor signature...");

        // check the signature length
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        // extract r, s and v variables.
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        // if the version is correct return the signer address
        if (v < 27) {
            // if v is 0 or 1, add 27 to convert it to 27 or 28
            if (v == 0) v = 28;
            if (v == 4) v = 28;
            if (v == 1) v = 27;
        } else {
            return signature;
        }

        // reconstruct the signature with the correct v value
        bytes memory newSignature = abi.encodePacked(r, s, v);

        console.log("\nFixed signature:");
        console.logBytes(newSignature);

        return newSignature;
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
            if (privateKeys[i] == 0 || privateKeys[i] == 1) {
                bytes memory hwSignature = _signUserOpWithHW(privateKeys[i], op, _entryPoint, chainID);
                signature = abi.encodePacked(signature, hwSignature);   
            }
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKeys[i], hash);
            if (i == 0) {
                signature = abi.encodePacked(r, s, v);
            } else {
                signature = abi.encodePacked(signature, r, s, v);
            }
        }
        return signature;
    }
}

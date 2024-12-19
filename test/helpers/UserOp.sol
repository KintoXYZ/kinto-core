// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {LibString} from "solady/utils/LibString.sol";

import "@aa/core/Helpers.sol";
import {UserOperationLib} from "@aa/core/UserOperationLib.sol";
import {IEntryPoint} from "@aa/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@aa/interfaces/PackedUserOperation.sol";
import {EntryPoint} from "@aa/core/EntryPoint.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import {KintoWallet} from "@kinto-core/wallet/KintoWallet.sol";
import {KintoWalletFactory} from "@kinto-core/wallet/KintoWalletFactory.sol";

import {SignerHelper} from "@kinto-core-test/helpers/SignerHelper.sol";

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

    uint256 public constant MAX_COST_OF_VERIFICATION = 530_000;
    uint256 public constant COST_OF_POST = 200_000;

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
    ) internal returns (PackedUserOperation memory op) {
        bytes memory callData;
        if (isBatch) {
            callData = abi.encodeCall(KintoWallet.executeBatch, (opParams.targets, opParams.values, opParams.bytesOps));
        } else {
            callData = abi.encodeCall(KintoWallet.execute, (target, value, bytesOp));
        }

        op = PackedUserOperation({
            sender: from,
            nonce: nonce,
            initCode: bytes(""),
            callData: callData,
            preVerificationGas: 21_000, // should also cover calldata cost.
            accountGasLimits: packAccountGasLimits(210_000, gasLimits[0]),
            gasFees: packAccountGasLimits(gasLimits[2], gasLimits[1]),
            paymasterAndData: paymaster != address(0)
                ? packPaymasterData(paymaster, MAX_COST_OF_VERIFICATION, COST_OF_POST, bytes(""))
                : bytes(""),
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
    ) internal returns (PackedUserOperation memory op) {
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
    ) internal returns (PackedUserOperation memory op) {
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
    ) internal returns (PackedUserOperation memory op) {
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
    ) internal returns (PackedUserOperation memory op) {
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

    /**
     * Pack the user operation data into bytes for hashing.
     * @param userOp - The user operation data.
     */
    function encodePackedUserOperation(PackedUserOperation memory userOp) internal pure returns (bytes memory ret) {
        address sender = userOp.sender;
        uint256 nonce = userOp.nonce;
        bytes32 hashInitCode = keccak256(userOp.initCode);
        bytes32 hashCallData = keccak256(userOp.callData);
        bytes32 accountGasLimits = userOp.accountGasLimits;
        uint256 preVerificationGas = userOp.preVerificationGas;
        bytes32 gasFees = userOp.gasFees;
        bytes32 hashPaymasterAndData = keccak256(userOp.paymasterAndData);

        return abi.encode(
            sender,
            nonce,
            hashInitCode,
            hashCallData,
            accountGasLimits,
            preVerificationGas,
            gasFees,
            hashPaymasterAndData
        );
    }

    function _getUserOpHash(PackedUserOperation memory op, IEntryPoint _entryPoint, uint256 chainID)
        internal
        pure
        returns (bytes32)
    {
        bytes32 opHash = keccak256(encodePackedUserOperation(op));
        // TODO: v7 have a different hashing
        return keccak256(abi.encode(opHash, address(_entryPoint), chainID));
    }

    function _signUserOp(
        PackedUserOperation memory op,
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

    function packAccountGasLimits(uint256 limit0, uint256 limit1) public pure returns (bytes32) {
        // Ensure the inputs fit into 128 bits each
        require(limit0 <= type(uint128).max, "limit0 too large");
        require(limit1 <= type(uint128).max, "limit1 too large");

        // Pack the values into bytes32
        bytes32 packed = bytes32((uint256(limit0) << 128) | uint256(limit1));

        return packed;
    }

    function packPaymasterData(
        address paymaster,
        uint256 paymasterVerificationGasLimit,
        uint256 postOpGasLimit,
        bytes memory paymasterData
    ) public pure returns (bytes memory) {
        require(paymasterVerificationGasLimit <= type(uint128).max, "VerificationGasLimit too large");
        require(postOpGasLimit <= type(uint128).max, "PostOpGasLimit too large");

        return bytes.concat(
            bytes20(paymaster), // Address is padded to 20 bytes
            bytes16(uint128(paymasterVerificationGasLimit)), // Pack verification gas limit (16 bytes)
            bytes16(uint128(postOpGasLimit)), // Pack post operation gas limit (16 bytes)
            paymasterData // Append additional paymaster data
        );
    }
}

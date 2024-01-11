// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@aa/interfaces/IEntryPoint.sol";
import "@aa/core/EntryPoint.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "../../src/wallet/KintoWallet.sol";
import "../../src/wallet/KintoWalletFactory.sol";

abstract contract UserOp is Test {
    using ECDSAUpgradeable for bytes32;

    // private keys
    uint256 _ownerPk = 1;
    uint256 _secondownerPk = 2;
    uint256 _userPk = 3;
    uint256 _user2Pk = 4;
    uint256 _upgraderPk = 5;
    uint256 _kycProviderPk = 6;
    uint256 _recovererPk = 7;
    uint256 _funderPk = 8;

    // users
    address payable _owner = payable(vm.addr(_ownerPk));
    address payable _secondowner = payable(vm.addr(_secondownerPk));
    address payable _user = payable(vm.addr(_userPk));
    address payable _user2 = payable(vm.addr(_user2Pk));
    address payable _upgrader = payable(vm.addr(_upgraderPk));
    address payable _kycProvider = payable(vm.addr(_kycProviderPk));
    address payable _recoverer = payable(vm.addr(_recovererPk));
    address payable _funder = payable(vm.addr(_funderPk));

    struct OperationParams {
        address[] targetContracts;
        uint256[] values;
        bytes[] bytesOps;
    }

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
        uint256[] calldata privateKeys
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

    function createUserOperation(
        uint256 _chainID,
        address _account,
        uint256 nonce,
        uint256[] calldata _privateKeyOwners,
        address _targetContract,
        uint256 value,
        bytes calldata _bytesOp
    ) public view returns (UserOperation memory op) {
        return this.createUserOperation(
            _chainID, _account, nonce, _privateKeyOwners, _targetContract, value, _bytesOp, address(0)
        );
    }

    function createUserOperation(
        uint256 _chainID,
        address _account,
        uint256 nonce,
        uint256[] calldata _privateKeyOwners,
        address _targetContract,
        uint256 value,
        bytes calldata _bytesOp,
        address _paymaster
    ) public view returns (UserOperation memory op) {
        op = UserOperation({
            sender: _account,
            nonce: nonce,
            initCode: bytes(""),
            callData: abi.encodeCall(KintoWallet.execute, (_targetContract, value, _bytesOp)),
            callGasLimit: 4000000, // generate from call simulation
            verificationGasLimit: 170000, // verification gas. will add create2 cost (3200+200*length) if initCode exists
            preVerificationGas: 21000, // should also cover calldata cost.
            maxFeePerGas: 1, // grab from current gas
            maxPriorityFeePerGas: 1e9, // grab from current gas
            paymasterAndData: abi.encodePacked(_paymaster),
            signature: bytes("")
        });
        op.signature = _signUserOp(op, KintoWallet(payable(_account)).entryPoint(), _chainID, _privateKeyOwners);
        return op;
    }

    function createUserOperation(
        uint256 _chainID,
        address _account,
        uint256 nonce,
        uint256[] calldata _privateKeyOwners,
        address _targetContract,
        uint256 value,
        bytes calldata _bytesOp,
        address _paymaster,
        uint256[3] calldata _gasLimits
    ) public view returns (UserOperation memory op) {
        op = UserOperation({
            sender: _account,
            nonce: nonce,
            initCode: bytes(""),
            callData: abi.encodeCall(KintoWallet.execute, (_targetContract, value, _bytesOp)),
            callGasLimit: _gasLimits[0], // generate from call simulation
            verificationGasLimit: 170000, // verification gas. will add create2 cost (3200+200*length) if initCode exists
            preVerificationGas: 21000, // should also cover calldata cost.
            maxFeePerGas: _gasLimits[1], // grab from current gas
            maxPriorityFeePerGas: _gasLimits[2], // grab from current gas
            paymasterAndData: abi.encodePacked(_paymaster),
            signature: bytes("")
        });
        op.signature = _signUserOp(op, KintoWallet(payable(_account)).entryPoint(), _chainID, _privateKeyOwners);
        return op;
    }

    function createUserOperationBatchWithPaymaster(
        uint256 _chainID,
        address _account,
        uint256 nonce,
        uint256[] calldata _privateKeyOwners,
        OperationParams calldata opParams,
        address _paymaster
    ) public view returns (UserOperation memory op) {
        op = _prepareUserOperation(_account, nonce, opParams, _paymaster);
        op.signature = _signUserOp(op, KintoWallet(payable(_account)).entryPoint(), _chainID, _privateKeyOwners);
    }

    function _prepareUserOperation(address _account, uint256 nonce, OperationParams memory opParams, address _paymaster)
        internal
        pure
        returns (UserOperation memory op)
    {
        op = UserOperation({
            sender: _account,
            nonce: nonce,
            initCode: bytes(""),
            callData: abi.encodeCall(
                KintoWallet.executeBatch, (opParams.targetContracts, opParams.values, opParams.bytesOps)
                ),
            callGasLimit: 4000000, // generate from call simulation
            verificationGasLimit: 170000, // verification gas
            preVerificationGas: 21000, // should also cover calldata cost.
            maxFeePerGas: 1, // grab from current gas
            maxPriorityFeePerGas: 1e9, // grab from current gas
            paymasterAndData: abi.encodePacked(_paymaster),
            signature: bytes("")
        });

        return op;
    }

    function _whitelistAppOp(
        uint256 _chainId,
        uint256[] memory pk,
        address wallet,
        uint256 startingNonce,
        address app,
        address _paymaster
    ) internal view returns (UserOperation memory userOp) {
        address[] memory targets = new address[](1);
        targets[0] = address(app);
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        return this.createUserOperation(
            _chainId,
            address(wallet),
            startingNonce,
            pk,
            address(wallet),
            0,
            abi.encodeWithSignature("whitelistApp(address[],bool[])", targets, flags),
            address(_paymaster)
        );
    }
}

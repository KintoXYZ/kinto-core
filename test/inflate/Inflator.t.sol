// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../SharedSetup.t.sol";
import "../../src/inflators/KintoInflator.sol";

contract InflatorNewUpgrade is KintoInflator {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(address _kintoWalletFactory) KintoInflator() {}
}

contract InflatorTest is SharedSetup {
    function setUp() public override {
        super.setUp();
        if (fork) {
            vm.prank(_inflator.owner());
            _inflator.transferOwnership(_owner);
        }
        vm.prank(_owner);
        _inflator.setKintoContract("SP", address(_paymaster));
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        InflatorNewUpgrade _newImpl = new InflatorNewUpgrade(address(_walletFactory));
        vm.prank(_owner);
        _inflator.upgradeTo(address(_newImpl));

        assertEq(InflatorNewUpgrade(payable(address(_inflator))).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner() public {
        InflatorNewUpgrade _newImpl = new InflatorNewUpgrade(address(_walletFactory));

        vm.expectRevert("Ownable: caller is not the owner");
        _inflator.upgradeTo(address(_newImpl));
    }

    /* ============ Compress/Inflate tests ============ */

    function testInflate() public {
        // 1. create user op
        UserOperation memory op = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );
        op.initCode = "0x1234567890";

        // 2. compress user op
        bytes memory compressed = _inflator.compress(op);
        bytes memory compressedSimple = _inflator.compressSimple(op);
        bytes memory encodedUserOp = abi.encode(op);

        uint256 compressionPercentage = 100 - (compressed.length * 100 / encodedUserOp.length);

        uint256 compressionSimplePercentage = 100 - (compressedSimple.length * 100 / encodedUserOp.length);

        // 3. decompress (inflate) user op
        UserOperation memory decompressed = _inflator.inflate(compressed);

        // assert that the decompressed user op is the same as the original
        assertEq(decompressed.sender, op.sender);
        assertEq(decompressed.nonce, op.nonce);
        assertEq(decompressed.initCode, op.initCode);
        assertEq(decompressed.callData, op.callData);
        assertEq(decompressed.callGasLimit, op.callGasLimit);
        assertEq(decompressed.verificationGasLimit, op.verificationGasLimit);
        assertEq(decompressed.preVerificationGas, op.preVerificationGas);
        assertEq(decompressed.maxFeePerGas, op.maxFeePerGas);
        assertEq(decompressed.maxPriorityFeePerGas, op.maxPriorityFeePerGas);
        assertEq(decompressed.paymasterAndData, op.paymasterAndData);
        assertEq(decompressed.signature, op.signature);
    }

    function testInflate_WhenDeployContract() public {
        // 1. create user op
        UserOperation memory op = _createUserOperation(
            address(_kintoWallet),
            address(_walletFactory),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature(
                "deployContract(bytes)", _ownerPk, 0, abi.encodePacked(type(Counter).creationCode), bytes32(0)
            ),
            address(_paymaster)
        );

        // 2. compress user op
        bytes memory compressed = _inflator.compress(op);
        bytes memory compressedSimple = _inflator.compressSimple(op);
        bytes memory encodedUserOp = abi.encode(op);

        uint256 compressionPercentage = 100 - (compressed.length * 100 / encodedUserOp.length);

        uint256 compressionSimplePercentage = 100 - (compressedSimple.length * 100 / encodedUserOp.length);

        // 3. decompress (inflate) user op
        UserOperation memory decompressed = _inflator.inflate(compressed);

        // assert that the decompressed user op is the same as the original
        assertEq(decompressed.sender, op.sender);
        assertEq(decompressed.nonce, op.nonce);
        assertEq(decompressed.initCode, op.initCode);
        assertEq(decompressed.callData, op.callData);
        assertEq(decompressed.callGasLimit, op.callGasLimit);
        assertEq(decompressed.verificationGasLimit, op.verificationGasLimit);
        assertEq(decompressed.preVerificationGas, op.preVerificationGas);
        assertEq(decompressed.maxFeePerGas, op.maxFeePerGas);
        assertEq(decompressed.maxPriorityFeePerGas, op.maxPriorityFeePerGas);
        assertEq(decompressed.paymasterAndData, op.paymasterAndData);
        assertEq(decompressed.signature, op.signature);
    }

    function testInflate_WhenTargetEqualsSender() public {
        // 1. create user op
        UserOperation memory op = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // 2. compress user op
        bytes memory compressed = _inflator.compress(op);
        bytes memory compressedSimple = _inflator.compressSimple(op);

        bytes memory encodedUserOp = abi.encode(op);

        uint256 compressionPercentage = 100 - (compressed.length * 100 / encodedUserOp.length);

        uint256 compressionSimplePercentage = 100 - (compressedSimple.length * 100 / encodedUserOp.length);

        // 3. decompress (inflate) user op
        UserOperation memory decompressed = _inflator.inflate(compressed);

        // assert that the decompressed user op is the same as the original
        assertEq(decompressed.sender, op.sender);
        assertEq(decompressed.nonce, op.nonce);
        assertEq(decompressed.initCode, op.initCode);
        assertEq(decompressed.callData, op.callData);
        assertEq(decompressed.callGasLimit, op.callGasLimit);
        assertEq(decompressed.verificationGasLimit, op.verificationGasLimit);
        assertEq(decompressed.preVerificationGas, op.preVerificationGas);
        assertEq(decompressed.maxFeePerGas, op.maxFeePerGas);
        assertEq(decompressed.maxPriorityFeePerGas, op.maxPriorityFeePerGas);
        assertEq(decompressed.paymasterAndData, op.paymasterAndData);
        assertEq(decompressed.signature, op.signature);
    }

    function testInflate_WhenNoPaymaster() public {
        // 1. create user op
        UserOperation memory op = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()")
        );
        op.paymasterAndData = "";

        // 2. compress user op
        bytes memory compressed = _inflator.compress(op);
        bytes memory compressedSimple = _inflator.compressSimple(op);

        bytes memory encodedUserOp = abi.encode(op);

        uint256 compressionPercentage = 100 - (compressed.length * 100 / encodedUserOp.length);

        uint256 compressionSimplePercentage = 100 - (compressedSimple.length * 100 / encodedUserOp.length);

        // 3. decompress (inflate) user op
        UserOperation memory decompressed = _inflator.inflate(compressed);

        // assert that the decompressed user op is the same as the original
        assertEq(decompressed.sender, op.sender);
        assertEq(decompressed.nonce, op.nonce);
        assertEq(decompressed.initCode, op.initCode);
        assertEq(decompressed.callData, op.callData);
        assertEq(decompressed.callGasLimit, op.callGasLimit);
        assertEq(decompressed.verificationGasLimit, op.verificationGasLimit);
        assertEq(decompressed.preVerificationGas, op.preVerificationGas);
        assertEq(decompressed.maxFeePerGas, op.maxFeePerGas);
        assertEq(decompressed.maxPriorityFeePerGas, op.maxPriorityFeePerGas);
        assertEq(decompressed.paymasterAndData, op.paymasterAndData);
        assertEq(decompressed.signature, op.signature);
    }

    function testInflate_WhenTargetIsKintoContract() public {
        vm.prank(_owner);
        _inflator.setKintoContract("KAR", address(_kintoAppRegistry));

        // 1. create user op
        UserOperation memory op = _createUserOperation(
            address(_kintoWallet),
            address(_kintoAppRegistry),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // 2. compress user op
        bytes memory compressed = _inflator.compress(op);
        bytes memory compressedSimple = _inflator.compressSimple(op);
        bytes memory encodedUserOp = abi.encode(op);

        uint256 compressionPercentage = 100 - (compressed.length * 100 / encodedUserOp.length);

        uint256 compressionSimplePercentage = 100 - (compressedSimple.length * 100 / encodedUserOp.length);

        // 3. decompress (inflate) user op
        UserOperation memory decompressed = _inflator.inflate(compressed);

        // assert that the decompressed user op is the same as the original
        assertEq(decompressed.sender, op.sender);
        assertEq(decompressed.nonce, op.nonce);
        assertEq(decompressed.initCode, op.initCode);
        assertEq(decompressed.callData, op.callData);
        assertEq(decompressed.callGasLimit, op.callGasLimit);
        assertEq(decompressed.verificationGasLimit, op.verificationGasLimit);
        assertEq(decompressed.preVerificationGas, op.preVerificationGas);
        assertEq(decompressed.maxFeePerGas, op.maxFeePerGas);
        assertEq(decompressed.maxPriorityFeePerGas, op.maxPriorityFeePerGas);
        assertEq(decompressed.paymasterAndData, op.paymasterAndData);
        assertEq(decompressed.signature, op.signature);
    }

    function testInflate_WhenExecuteBatch() public {
        // 1. create batched user op
        address[] memory targets = new address[](2);
        targets[0] = address(_kintoWallet);
        targets[1] = address(counter);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSignature("recoverer()");
        calls[1] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation memory op = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        // 2. compress user op
        bytes memory compressed = _inflator.compress(op);
        bytes memory compressedSimple = _inflator.compressSimple(op);
        bytes memory encodedUserOp = abi.encode(op);

        uint256 compressionPercentage = 100 - (compressed.length * 100 / encodedUserOp.length);

        uint256 compressionSimplePercentage = 100 - (compressedSimple.length * 100 / encodedUserOp.length);

        // 3. decompress (inflate) user op
        UserOperation memory decompressed = _inflator.inflate(compressed);

        // assert that the decompressed user op is the same as the original
        assertEq(decompressed.sender, op.sender);
        assertEq(decompressed.nonce, op.nonce);
        assertEq(decompressed.initCode, op.initCode);
        assertEq(decompressed.callData, op.callData);
        assertEq(decompressed.callGasLimit, op.callGasLimit);
        assertEq(decompressed.verificationGasLimit, op.verificationGasLimit);
        assertEq(decompressed.preVerificationGas, op.preVerificationGas);
        assertEq(decompressed.maxFeePerGas, op.maxFeePerGas);
        assertEq(decompressed.maxPriorityFeePerGas, op.maxPriorityFeePerGas);
        assertEq(decompressed.paymasterAndData, op.paymasterAndData);
        assertEq(decompressed.signature, op.signature);
    }

    function testInflate_WhenCustomGasParams() public {
        // 1. create batched user op
        address[] memory targets = new address[](2);
        targets[0] = address(_kintoWallet);
        targets[1] = address(counter);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSignature("recoverer()");
        calls[1] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation memory op = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );
        op.callGasLimit = 250_000;
        op.verificationGasLimit = 230_000;
        op.preVerificationGas = 1_500_000;
        op.maxFeePerGas = 138_000_000;
        op.maxPriorityFeePerGas = 690_000;

        // 2. compress user op
        bytes memory compressed = _inflator.compress(op);
        bytes memory compressedSimple = _inflator.compressSimple(op);
        bytes memory encodedUserOp = abi.encode(op);

        uint256 compressionPercentage = 100 - (compressed.length * 100 / encodedUserOp.length);

        uint256 compressionSimplePercentage = 100 - (compressedSimple.length * 100 / encodedUserOp.length);

        // 3. decompress (inflate) user op
        UserOperation memory decompressed = _inflator.inflate(compressed);

        // assert that the decompressed user op is the same as the original
        assertEq(decompressed.sender, op.sender);
        assertEq(decompressed.nonce, op.nonce);
        assertEq(decompressed.initCode, op.initCode);
        assertEq(decompressed.callData, op.callData);
        assertEq(decompressed.callGasLimit, op.callGasLimit);
        assertEq(decompressed.verificationGasLimit, op.verificationGasLimit);
        assertEq(decompressed.preVerificationGas, op.preVerificationGas);
        assertEq(decompressed.maxFeePerGas, op.maxFeePerGas);
        assertEq(decompressed.maxPriorityFeePerGas, op.maxPriorityFeePerGas);
        assertEq(decompressed.paymasterAndData, op.paymasterAndData);
        assertEq(decompressed.signature, op.signature);
    }

    function testInflate_WhenSimpleInflate() public {
        // 1. create user op
        UserOperation memory op = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // 2. compress user op
        bytes memory compressedSimple = _inflator.compressSimple(op);

        UserOperation memory decompressedSimple = _inflator.inflateSimple(compressedSimple);

        // assert that the decompressed user op is the same as the original
        assertEq(decompressedSimple.sender, op.sender);
        assertEq(decompressedSimple.nonce, op.nonce);
        assertEq(decompressedSimple.initCode, op.initCode);
        assertEq(decompressedSimple.callData, op.callData);
        assertEq(decompressedSimple.callGasLimit, op.callGasLimit);
        assertEq(decompressedSimple.verificationGasLimit, op.verificationGasLimit);
        assertEq(decompressedSimple.preVerificationGas, op.preVerificationGas);
        assertEq(decompressedSimple.maxFeePerGas, op.maxFeePerGas);
        assertEq(decompressedSimple.maxPriorityFeePerGas, op.maxPriorityFeePerGas);
        assertEq(decompressedSimple.paymasterAndData, op.paymasterAndData);
        assertEq(decompressedSimple.signature, op.signature);
    }
}

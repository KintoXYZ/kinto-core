// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@aa/interfaces/IEntryPoint.sol";

import "../../SharedSetup.t.sol";

contract ExecuteBatchTest is SharedSetup {
    function testExecuteBatch_WhenPaymaster() public {
        // prep batch
        address[] memory targets = new address[](1);
        targets[0] = address(counter);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // we want to do 3 calls: whitelistApp, increment counter and increment counter2
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
    }

    function testExecuteBatch_RevertWhen_NoPaymasterNorPrefund() public {
        // prep batch
        address[] memory targets = new address[](1);
        targets[0] = address(counter);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation memory userOp =
            _createUserOperation(address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(0));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        vm.expectRevert(abi.encodeWithSignature("FailedOp(uint256,string)", 0, "AA21 didn't pay prefund"));
        _entryPoint.handleOps(userOps, payable(_owner));
    }

    function testExecuteBatch_WhenPrefund() public {
        // prefund wallet
        vm.deal(address(_kintoWallet), 1 ether);

        // prep batch
        address[] memory targets = new address[](1);
        targets[0] = address(counter);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // we want to do 3 calls: whitelistApp, increment counter and increment counter2
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] =
            _createUserOperation(address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(0));

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
    }

    function testExecuteBatch_WhenMultipleOps_WhenPaymaster() public {
        // prep batch
        address[] memory targets = new address[](2);
        targets[0] = address(counter);
        targets[1] = address(counter);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;

        // we want to do 2 calls
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSignature("increment()");
        calls[1] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 2);
    }

    function testExecuteBatch_RevertWhen_AppIsNotWhitelisted() public {
        // remove app from whitelist
        whitelistApp(address(counter), false);

        // prep batch
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
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq("KW: contract not whitelisted");
    }
}

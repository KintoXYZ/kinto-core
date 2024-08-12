// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@aa/interfaces/IEntryPoint.sol";

import "@kinto-core-test/SharedSetup.t.sol";
import {IKintoAppRegistry} from "@kinto-core/interfaces/IKintoAppRegistry.sol";

contract ExecuteBatchTest is SharedSetup {
    /* ============ Paymaster ============ */

    function testExecuteBatch_WhenPaymaster() public {
        Counter counter2 = new Counter();

        address[] memory targets = new address[](3);
        targets[0] = address(_kintoWallet);
        targets[1] = address(counter2);
        targets[2] = address(counter2);

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        address[] memory whitelistTargets = new address[](1);
        whitelistTargets[0] = address(counter2);
        bool[] memory flags = new bool[](1);
        flags[0] = true;

        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSelector(IKintoWallet.whitelistApp.selector, whitelistTargets, flags);
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");

        vm.prank(address(_entryPoint));
        _kintoWallet.executeBatch(targets, values, calls);

        assertEq(counter2.count(), 2);
    }

    function testExecuteBatch_RevertWhen_NoPaymasterNorPrefund() public {
        // remove any balance from the wallet
        vm.deal(address(_kintoWallet), 0);

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

    /* ============ executeBatch ============ */

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

        vm.prank(address(_entryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(IKintoWallet.AppNotWhitelisted.selector, address(counter), address(counter))
        );
        _kintoWallet.executeBatch(targets, values, calls);
    }

    function testExecuteBatch_RevertWhen_LengthMismatch() public {
        // remove app from whitelist
        whitelistApp(address(counter), false);

        // prep batch
        address[] memory targets = new address[](2);
        targets[0] = address(_kintoWallet);
        targets[1] = address(counter);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSignature("recoverer()");

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
        assertRevertReasonEq(IKintoWallet.LengthMismatch.selector);
    }

    function testExecuteBatch_RevertWhen_LengthMismatch2() public {
        // remove app from whitelist
        whitelistApp(address(counter), false);

        // prep batch
        address[] memory targets = new address[](1);
        targets[0] = address(_kintoWallet);

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
        assertRevertReasonEq(IKintoWallet.LengthMismatch.selector);
    }

    function testExecuteBatch_RevertWhen_AppNotSponsored() public {
        address notSponsored = address(new Counter());

        // Prepare batch execution data
        address[] memory targets = new address[](2);
        targets[0] = notSponsored; // This is sponsored
        targets[1] = address(counter); // This is the app, but not sponsored

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory callData = new bytes[](2);
        callData[0] = abi.encodeWithSelector(Counter.increment.selector);
        callData[1] = abi.encodeWithSelector(Counter.increment.selector);

        // Attempt to execute the batch
        vm.prank(address(_entryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(IKintoWallet.AppNotSponsored.selector, address(counter), address(notSponsored))
        );
        _kintoWallet.executeBatch(targets, values, callData);

        // Verify that no counters were incremented
        assertEq(Counter(notSponsored).count(), 0);
        assertEq(counter.count(), 0);
    }
}

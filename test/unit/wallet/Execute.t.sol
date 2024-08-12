// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";
import {IEntryPoint} from "@aa/core/BaseAccount.sol";

contract ExecuteTest is SharedSetup {
    function testExecute() public {
        vm.prank(address(_entryPoint));
        _kintoWallet.execute(address(counter), 0, abi.encodeWithSelector(Counter.increment.selector));

        assertEq(counter.count(), 1);
    }

    function testExecute_RevertWhen_NoPaymasterNorPrefund() public {
        // remove any balance from the wallet
        vm.deal(address(_kintoWallet), 0);

        // send a transaction to the counter contract through our wallet without a paymaster and without prefunding the wallet
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()")
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        vm.expectRevert(abi.encodeWithSignature("FailedOp(uint256,string)", 0, "AA21 didn't pay prefund"));
        _entryPoint.handleOps(userOps, payable(_owner));
    }

    function testExecute_WhenPrefund() public {
        // prefund wallet
        vm.deal(address(_kintoWallet), 1 ether);

        // send op without a paymaster but prefunding the wallet
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()")
        );

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
    }

    function testExecute_WhenMultipleOps_WhenPaymaster() public {
        uint256 nonce = _kintoWallet.getNonce();
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            nonce,
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        userOps[1] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            nonce + 1,
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 2);
    }

    function testExecute_RevertWhen_AppIsNotWhitelisted() public {
        // remove app from whitelist
        whitelistApp(address(counter), false);

        // create Counter increment user op
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // execute transaction
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(IKintoWallet.AppNotWhitelisted.selector);
        assertEq(counter.count(), 0);
    }

    function testExecute_WhenAppSponsor() public {
        // remove any balance from the wallet
        vm.deal(address(_kintoWallet), 0);

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // execute the transactions via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
    }

    function testExecute_RevertWhenNoSponsor() public {
        // remove any balance from the wallet
        vm.deal(address(_kintoWallet), 0);

        Counter other = new Counter();

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(other),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                uint256(0),
                "AA33 reverted",
                abi.encodePacked(ISponsorPaymaster.DepositTooLow.selector)
            )
        );

        _entryPoint.handleOps(userOps, payable(_owner));

        assertEq(other.count(), 0);
    }
}

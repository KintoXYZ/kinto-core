// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";
import {IEntryPoint} from "@aa/core/BaseAccount.sol";

contract ExecuteTest is SharedSetup {
    address public systemApp;
    Counter public systemCounter;

    function setUp() public override {
        super.setUp();

        // Deploy a new counter to be used as a system app
        systemCounter = new Counter();
        systemApp = address(systemCounter);

        // Set up the system app in the registry
        address[] memory newSystemApps = new address[](1);
        newSystemApps[0] = systemApp;
        vm.prank(_owner);
        _kintoAppRegistry.updateSystemApps(newSystemApps);
    }

    /* ============ Paymaster ============ */

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

    function testExecute_RevertWhenDepositTooLow() public {
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
    /* ============ Execute ============ */

    function testExecute() public {
        vm.prank(address(_entryPoint));
        _kintoWallet.execute(address(counter), 0, abi.encodeWithSelector(Counter.increment.selector));

        assertEq(counter.count(), 1);
    }

    function testExecute_RevertWhen_AppIsNotWhitelisted() public {
        // remove app from whitelist
        whitelistApp(address(counter), false);

        vm.prank(address(_entryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(IKintoWallet.AppNotWhitelisted.selector, address(counter), address(counter))
        );
        _kintoWallet.execute(address(counter), 0, abi.encodeWithSelector(Counter.increment.selector));

        assertEq(counter.count(), 0);
    }

    function testExecute_WhenAppSponsor() public {
        // TODO: Use explicit sponsor contracts
        vm.prank(address(_entryPoint));
        _kintoWallet.execute(address(counter), 0, abi.encodeWithSelector(Counter.increment.selector));

        assertEq(counter.count(), 1);
    }

    function testExecute_WhenSystemApp() public {
        vm.prank(address(_entryPoint));
        _kintoWallet.execute(systemApp, 0, abi.encodeWithSelector(Counter.increment.selector));

        assertEq(systemCounter.count(), 1);
    }
}

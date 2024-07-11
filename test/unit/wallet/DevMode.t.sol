// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";
import {KintoWallet} from "@kinto-core/wallet/KintoWallet.sol";

contract DevModeWalletTest is SharedSetup {
    function setUp() public override {
        super.setUp();
    }

    function testSetDevMode() public {
        vm.prank(address(_kintoWallet));
        vm.expectEmit(true, true, true, true);
        emit KintoWallet.DevModeChanged(1, 0);
        _kintoWallet.setDevMode(1);

        assertEq(_kintoWallet.devMode(), 1);
    }
}


// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";

contract DevModeWalletTest is SharedSetup {
    function setUp() public override {
        super.setUp();
    }

    function testSetDevMode() public {
        vm.prank(address(_kintoWallet));
        _kintoWallet.setDevMode(1);

        assertEq(_kintoWallet.devMode(), 1);
    }
}


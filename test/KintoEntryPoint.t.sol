// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./SharedSetup.t.sol";

contract KintoEntryPointTest is SharedSetup {
    function testUp() public override {
        assertEq(_entryPoint.walletFactory(), address(_walletFactory));
    }

    /* ============ Deployment tests ============ */

    function testCannotResetWalletFactoryAddress() public {
        vm.startPrank(_owner);
        vm.expectRevert("AA36 wallet factory already set");
        _entryPoint.setWalletFactory(address(0));
        vm.stopPrank();
    }
}

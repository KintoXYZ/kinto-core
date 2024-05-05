// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";

contract KintoEntryPointTest is SharedSetup {
    function testUp() public view override {
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

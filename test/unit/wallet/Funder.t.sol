// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";
import "@kinto-core-test/helpers/ArrayHelpers.sol";

contract FunderTest is SharedSetup {
    using ArrayHelpers for *;

    function testUp() public override {
        super.testUp();

        assertEq(_kintoWallet.isFunderWhitelisted(_owner), true);
        assertEq(_kintoWallet.isFunderWhitelisted(_user), false);
        assertEq(_kintoWallet.isFunderWhitelisted(_user2), false);
    }

    function testSetFunderWhitelist() public {
        vm.prank(address(_kintoWallet));
        _kintoWallet.setFunderWhitelist([address(23)].toMemoryArray(), [true].toMemoryArray());

        assertEq(_kintoWallet.isFunderWhitelisted(address(23)), true);
    }

    function testSetFunderWhitelist_RevertWhen_LengthMismatch() public {
        vm.prank(address(_kintoWallet));
        vm.expectRevert(abi.encodeWithSelector(IKintoWallet.LengthMismatch.selector));
        _kintoWallet.setFunderWhitelist([address(23), address(24)].toMemoryArray(), [true].toMemoryArray());
    }
}

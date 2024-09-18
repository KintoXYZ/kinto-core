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

    function testIsFunderWhitelisted() public view {
        assertEq(_kintoWallet.isFunderWhitelisted(0x0f1b7bd7762662B23486320AA91F30312184f70C), true);
        assertEq(_kintoWallet.isFunderWhitelisted(0xb7DfE09Cf3950141DFb7DB8ABca90dDef8d06Ec0), true);
        assertEq(_kintoWallet.isFunderWhitelisted(0x361C9A99Cf874ec0B0A0A89e217Bf0264ee17a5B), true);
        assertEq(_kintoWallet.isFunderWhitelisted(_kintoWallet.getAccessPoint()), true);
    }
}

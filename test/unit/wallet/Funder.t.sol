// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";

contract FunderTest is SharedSetup {
    /* ============ Funder Whitelist ============ */

    function testUp() public override {
        super.testUp();

        assertEq(_kintoWallet.isFunderWhitelisted(_owner), true);
        assertEq(_kintoWallet.isFunderWhitelisted(_user), false);
        assertEq(_kintoWallet.isFunderWhitelisted(_user2), false);
    }

    function testSetFunderWhitelist() public {
        address[] memory funders = new address[](1);
        funders[0] = address(23);

        bool[] memory flags = new bool[](1);
        flags[0] = true;

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("setFunderWhitelist(address[],bool[])", funders, flags),
            address(_paymaster)
        );

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWallet.isFunderWhitelisted(address(23)), true);
    }

    function testSetFunderWhitelist_RevertWhen_LengthMismatch() public {
        address[] memory funders = new address[](2);
        funders[0] = address(23);
        funders[1] = address(24);

        bool[] memory flags = new bool[](1);
        flags[0] = true;

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("setFunderWhitelist(address[],bool[])", funders, flags),
            address(_paymaster)
        );

        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(IKintoWallet.LengthMismatch.selector);
    }
}

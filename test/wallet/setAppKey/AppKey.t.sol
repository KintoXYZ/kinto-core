// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import "../../SharedSetup.t.sol";

contract AppKeyTest is SharedSetup {
    /* ============ App Key ============ */

    function testSetAppKey() public {
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("setAppKey(address,address)", address(counter), _user),
            address(_paymaster)
        );

        vm.expectEmit(true, true, true, false);
        emit AppKeyCreated(address(counter), _user);
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWallet.appSigner(address(counter)), _user);
    }

    // todo: we may want to remove this requirement from the KintoWallet since anyways
    // we always check for the app to be whitelisted regardless if using app key or not
    function testSetAppKey_RevertWhen_AppIsNotWhitelisted() public {
        // remove app from whitelist
        whitelistApp(address(counter), false);

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("setAppKey(address,address)", address(_engenCredits), _user),
            address(_paymaster)
        );

        address appSignerBefore = _kintoWallet.appSigner(address(_engenCredits));

        // @dev handleOps fails silently (does not revert)
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(IKintoWallet.AppNotWhitelisted.selector);
        assertEq(_kintoWallet.appSigner(address(_engenCredits)), appSignerBefore);
    }
}

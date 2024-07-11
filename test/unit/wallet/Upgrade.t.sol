// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";

contract UpgradeTest is SharedSetup {
    /* ============ Upgrade tests ============ */

    // FIXME: I think these upgrade tests are wrong because, basically, the KintoWallet.sol does not have
    // an upgrade function. The upgrade function is in the UUPSUpgradeable.sol contract and the wallet uses the Beacon proxy.
    function test_RevertWhen_OwnerCannotUpgrade() public {
        // deploy a new implementation
        KintoWallet _newImplementation = new KintoWallet(_entryPoint, _kintoID, _kintoAppRegistry, _walletFactory);

        // try calling upgradeTo from _owner wallet to upgrade _owner wallet
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("upgradeTo(address)", address(_newImplementation)),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // execute the transaction via the entry point and expect a revert event
        // @dev handleOps fails silently (does not revert)
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(_entryPoint.getUserOpHash(userOp), userOp.sender, userOp.nonce, bytes(""));
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq("Address: low-level call with value failed");
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner() public {
        approveKYC(_kycProvider, _user, _userPk);

        // create a wallet for _user
        vm.prank(_user);
        IKintoWallet userWallet = _walletFactory.createAccount(_user, _recoverer, 0);

        // deploy a new implementation
        KintoWallet _newImplementation = new KintoWallet(_entryPoint, _kintoID, _kintoAppRegistry, _walletFactory);

        // try calling upgradeTo from _user wallet to upgrade _owner wallet
        privateKeys[0] = _userPk;

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(userWallet),
            address(_kintoWallet),
            userWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("upgradeTo(address)", address(_newImplementation)),
            address(_paymaster)
        );

        // @dev handleOps seems to fail silently (does not revert)
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );

        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(IKintoWallet.AppNotWhitelisted.selector);
    }
}

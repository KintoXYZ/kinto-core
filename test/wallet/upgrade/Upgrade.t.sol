// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import "../../SharedSetup.t.sol";

contract PolicyTest is SharedSetup {
    /* ============ Upgrade tests ============ */

    // FIXME: I think these upgrade tests are wrong because, basically, the KintoWallet.sol does not have
    // an upgrade function. The upgrade function is in the UUPSUpgradeable.sol contract and the wallet uses the Beacon proxy.
    function test_RevertWhen_OwnerCannotUpgrade() public {
        // deploy a new implementation
        KintoWallet _newImplementation = new KintoWallet(_entryPoint, _kintoID, _kintoAppRegistry);

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
        // create a wallet for _user
        approveKYC(_kycProvider, _user, _userPk);
        vm.broadcast(_user);
        IKintoWallet userWallet = _walletFactory.createAccount(_user, _recoverer, 0);

        // deploy a new implementation
        KintoWallet _newImplementation = new KintoWallet(_entryPoint, _kintoID, _kintoAppRegistry);

        // try calling upgradeTo from _user wallet to upgrade _owner wallet
        uint256 nonce = userWallet.getNonce();
        privateKeys[0] = _userPk;

        UserOperation memory userOp = _createUserOperation(
            address(userWallet),
            address(_kintoWallet),
            nonce,
            privateKeys,
            abi.encodeWithSignature("upgradeTo(address)", address(_newImplementation)),
            address(_paymaster)
        );

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // @dev handleOps seems to fail silently (does not revert)
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(_entryPoint.getUserOpHash(userOp), userOp.sender, userOp.nonce, bytes(""));

        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(IKintoWallet.AppNotWhitelisted.selector);

        vm.stopPrank();
    }
}

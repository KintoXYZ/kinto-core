// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import "../../SharedSetup.t.sol";

contract UpgradeTest is SharedSetup {
    /* ============ Upgrade tests ============ */

    // FIXME: I think these upgrade tests are wrong because, basically, the KintoWallet.sol does not have
    // an upgrade function. The upgrade function is in the UUPSUpgradeable.sol contract and the wallet uses the Beacon proxy.

    function testUpgradeTo_RevertWhen_CallerIsNotOwner() public {
        approveKYC(_kycProvider, _user, _userPk);

        // create a wallet for _user
        vm.prank(_user);
        IKintoWallet userWallet = _walletFactory.createAccount(_user, _recoverer, 0);

        // deploy a new implementation
        KintoWallet _newImplementation = new KintoWallet(_entryPoint, _kintoID, _kintoAppRegistry);

        // try calling upgradeTo from _user wallet to upgrade _owner wallet
        privateKeys[0] = _userPk;

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(userWallet),
            address(_kintoWallet),
            userWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(_newImplementation), bytes("")),
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

        vm.stopPrank();
    }
}

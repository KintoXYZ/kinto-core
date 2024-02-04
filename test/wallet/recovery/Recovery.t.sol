// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import "../../SharedSetup.t.sol";

contract RecoveryTest is SharedSetup {
    /* ============ Recovery tests ============ */

    function testStartRecovery() public {
        vm.prank(address(_walletFactory));
        _kintoWallet.startRecovery();
        assertEq(_kintoWallet.inRecovery(), block.timestamp);
    }

    function testStartRecovery_RevertWhen_DirectCall(address someone) public {
        vm.assume(someone != address(_walletFactory));
        vm.prank(someone);
        vm.expectRevert("KW: only factory");
        _kintoWallet.startRecovery();
    }

    function testRecoverAccountSuccessfully() public {
        assertEq(_kintoWallet.owners(0), _owner);

        // start Recovery
        vm.prank(address(_walletFactory));
        _kintoWallet.startRecovery();
        assertEq(_kintoWallet.inRecovery(), block.timestamp);

        // mint NFT to new owner and burn old
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](0);

        vm.startPrank(_kycProvider);
        _kintoID.mintIndividualKyc(sigdata, traits);
        sigdata = _auxCreateSignature(_kintoID, _owner, 1, block.timestamp + 1000);
        _kintoID.burnKYC(sigdata);
        vm.stopPrank();

        assertEq(_kintoID.isKYC(_user), true);

        // pass recovery time
        vm.warp(block.timestamp + _kintoWallet.RECOVERY_TIME() + 1);

        address[] memory users = new address[](1);
        users[0] = _user;
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);

        vm.prank(_kycProvider);
        _kintoID.monitor(users, updates);

        vm.prank(address(_walletFactory));
        _kintoWallet.completeRecovery(users);

        assertEq(_kintoWallet.inRecovery(), 0);
        assertEq(_kintoWallet.owners(0), _user);
    }

    function testComplete_RevertWhen_RecoverWithoutBurningOldOwner() public {
        assertEq(_kintoWallet.owners(0), _owner);

        // start recovery
        vm.prank(address(_walletFactory));
        _kintoWallet.startRecovery();
        assertEq(_kintoWallet.inRecovery(), block.timestamp);

        // approve KYC for _user (mint NFT)
        approveKYC(_kycProvider, _user, _userPk);
        assertEq(_kintoID.isKYC(_user), true);

        // pass recovery time
        vm.warp(block.timestamp + _kintoWallet.RECOVERY_TIME() + 1);

        // monitor AML
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);

        address[] memory users = new address[](1);
        users[0] = _user;

        vm.prank(_kycProvider);
        _kintoID.monitor(users, updates);

        // complete recovery
        vm.prank(address(_walletFactory));
        vm.expectRevert("KW-fr: Old KYC must be burned");
        _kintoWallet.completeRecovery(users);
    }

    function testComplete_RevertWhen_RecoverWithoutNewOwnerKYCd() public {
        assertEq(_kintoWallet.owners(0), _owner);

        // start recovery
        vm.prank(address(_walletFactory));
        _kintoWallet.startRecovery();
        assertEq(_kintoWallet.inRecovery(), block.timestamp);

        // burn old owner NFT
        revokeKYC(_kycProvider, _owner, _ownerPk);
        assertEq(_kintoID.isKYC(_owner), false);

        // pass recovery time
        vm.warp(block.timestamp + _kintoWallet.RECOVERY_TIME() + 1);

        // complete recovery
        assertEq(_kintoID.isKYC(_user), false); // new owner is not KYC'd
        address[] memory users = new address[](1);
        users[0] = _user;
        vm.prank(address(_walletFactory));
        vm.expectRevert("KW-rs: KYC Required");
        _kintoWallet.completeRecovery(users);
    }

    function testComplete_RevertWhen_RecoverNotEnoughTime() public {
        assertEq(_kintoWallet.owners(0), _owner);

        // start recovery
        vm.prank(address(_walletFactory));
        _kintoWallet.startRecovery();
        assertEq(_kintoWallet.inRecovery(), block.timestamp);

        // burn old owner NFT
        revokeKYC(_kycProvider, _owner, _ownerPk);
        assertEq(_kintoID.isKYC(_owner), false);

        // approve KYC for _user (mint NFT)
        approveKYC(_kycProvider, _user, _userPk);
        assertEq(_kintoID.isKYC(_user), true);

        // pass recovery time (not enough)
        vm.warp(block.timestamp + _kintoWallet.RECOVERY_TIME() - 1);

        // monitor AML
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);

        address[] memory users = new address[](1);
        users[0] = _user;

        vm.prank(_kycProvider);
        _kintoID.monitor(users, updates);

        // complete recovery
        vm.prank(address(_walletFactory));
        vm.expectRevert("KW-fr: too early");
        _kintoWallet.completeRecovery(users);
    }

    function testCancelRecovery() public {
        vm.prank(address(_walletFactory));
        _kintoWallet.startRecovery();
        assertEq(_kintoWallet.inRecovery(), block.timestamp);

        vm.prank(address(_kintoWallet));
        _kintoWallet.cancelRecovery();
    }

    function testCancelRecovery_RevertWhen_CallerIsNotWallet() public {
        vm.prank(address(_walletFactory));
        _kintoWallet.startRecovery();
        assertEq(_kintoWallet.inRecovery(), block.timestamp);

        vm.expectRevert("KW: only self");
        _kintoWallet.cancelRecovery();
    }

    function testChangeRecoverer_RevertWhen_CallerIsNotFactory() public {
        vm.expectEmit(true, true, true, true);
        emit RecovererChanged(address(1), _kintoWallet.recoverer());
        vm.prank(address(_walletFactory));
        _kintoWallet.changeRecoverer(payable(address(1)));
    }

    function testChangeRecoverer_RevertWhen_CallerIsNotFactory(address someone) public {
        vm.assume(someone != address(_walletFactory));
        vm.expectRevert("KW: only factory");
        _kintoWallet.changeRecoverer(payable(address(_kintoWallet)));
    }

    function testChangeRecoverer_RevertWhen_SameRecoverer() public {
        address recoverer = _kintoWallet.recoverer();
        vm.prank(address(_walletFactory));
        vm.expectRevert("KW-cr: invalid address");
        _kintoWallet.changeRecoverer(payable(recoverer));
    }

    function testChangeRecoverer_RevertWhen_ZeroAddress() public {
        vm.prank(address(_walletFactory));
        vm.expectRevert("KW-cr: invalid address");
        _kintoWallet.changeRecoverer(payable(address(0)));
    }
}

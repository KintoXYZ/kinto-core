// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";

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
        vm.expectRevert(IKintoWallet.OnlyFactory.selector);
        _kintoWallet.startRecovery();
    }

    function testRecoverAccountSuccessfully() public {
        assertEq(_kintoWallet.owners(0), _owner);

        // start Recovery
        vm.prank(address(_walletFactory));
        _kintoWallet.startRecovery();
        assertEq(_kintoWallet.inRecovery(), block.timestamp);

        // mint NFT to new owner
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](0);
        vm.prank(_kycProvider);
        _kintoID.mintIndividualKyc(sigdata, traits);

        // burn old NFT
        sigdata = _auxCreateSignature(_kintoID, _owner, _ownerPk, block.timestamp + 1000);
        vm.prank(_kycProvider);
        _kintoID.burnKYC(sigdata);

        assertEq(_kintoID.isKYC(_user), true);
        assertEq(_kintoID.isKYC(_owner), false);

        // pass recovery time
        vm.warp(block.timestamp + _kintoWallet.RECOVERY_TIME() + 1);

        // trigger monitor
        address[] memory users = new address[](1);
        users[0] = _user;
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);

        vm.prank(_kycProvider);
        _kintoID.monitor(users, updates);

        // complete recovery
        vm.prank(address(_walletFactory));
        _kintoWallet.completeRecovery(users);

        assertEq(_kintoWallet.inRecovery(), 0);
        assertEq(_kintoWallet.owners(0), _user);
    }

    function testRecoverWalletMultipleSigners() public {
        address[] memory signers = new address[](2);
        signers[0] = _owner;
        signers[1] = _user;

        uint8 MINUS_ONE_SIGNER = _kintoWallet.MINUS_ONE_SIGNER();
        vm.prank(address(_kintoWallet));
        _kintoWallet.resetSigners(signers, MINUS_ONE_SIGNER);

        assertEq(_kintoWallet.owners(0), _owner);

        // start Recovery
        vm.prank(address(_walletFactory));
        _kintoWallet.startRecovery();
        assertEq(_kintoWallet.inRecovery(), block.timestamp);

        // mint NFT to new owner
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](0);
        vm.prank(_kycProvider);
        _kintoID.mintIndividualKyc(sigdata, traits);

        // burn old NFT
        sigdata = _auxCreateSignature(_kintoID, _owner, _ownerPk, block.timestamp + 1000);
        vm.prank(_kycProvider);
        _kintoID.burnKYC(sigdata);

        assertEq(_kintoID.isKYC(_user), true);
        assertEq(_kintoID.isKYC(_owner), false);

        // pass recovery time
        vm.warp(block.timestamp + _kintoWallet.RECOVERY_TIME() + 1);

        // trigger monitor
        address[] memory users = new address[](1);
        users[0] = _user;
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);

        vm.prank(_kycProvider);
        _kintoID.monitor(users, updates);

        // complete recovery
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
        vm.expectRevert(IKintoWallet.OwnerKYCMustBeBurned.selector);
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
        vm.expectRevert(IKintoWallet.OwnerKYCMustBeBurned.selector);
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
        vm.expectRevert(IKintoWallet.RecoveryTimeNotElapsed.selector);
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

        vm.expectRevert(IKintoWallet.OnlySelf.selector);
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
        vm.expectRevert(IKintoWallet.OnlyFactory.selector);
        _kintoWallet.changeRecoverer(payable(address(_kintoWallet)));
    }

    function testChangeRecoverer_RevertWhen_SameRecoverer() public {
        address recoverer = _kintoWallet.recoverer();
        vm.prank(address(_walletFactory));
        vm.expectRevert(IKintoWallet.InvalidRecoverer.selector);
        _kintoWallet.changeRecoverer(payable(recoverer));
    }

    function testChangeRecoverer_RevertWhen_ZeroAddress() public {
        vm.prank(address(_walletFactory));
        vm.expectRevert(IKintoWallet.InvalidRecoverer.selector);
        _kintoWallet.changeRecoverer(payable(address(0)));
    }
}

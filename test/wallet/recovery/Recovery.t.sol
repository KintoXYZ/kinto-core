// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@aa/interfaces/IEntryPoint.sol";

import "../../../../src/interfaces/IKintoWallet.sol";

import "../../../../src/wallet/KintoWallet.sol";
import "../../../../src/sample/Counter.sol";

import "../../harness/KintoWalletHarness.sol";
import {UserOp} from "../../helpers/UserOp.sol";
import {AATestScaffolding} from "../../helpers/AATestScaffolding.sol";

contract RecoveryTest is AATestScaffolding, UserOp {
    uint256[] privateKeys;

    // constants
    uint256 constant SIG_VALIDATION_FAILED = 1;

    // events
    event UserOperationRevertReason(
        bytes32 indexed userOpHash, address indexed sender, uint256 nonce, bytes revertReason
    );
    event KintoWalletInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event WalletPolicyChanged(uint256 newPolicy, uint256 oldPolicy);
    event RecovererChanged(address indexed newRecoverer, address indexed recoverer);

    function setUp() public {
        deployAAScaffolding(_owner, 1, _kycProvider, _recoverer);

        // Add paymaster to _kintoWallet
        _fundSponsorForApp(address(_kintoWallet));

        // Default tests to use 1 private key for simplicity
        privateKeys = new uint256[](1);

        // Default tests to use _ownerPk unless otherwise specified
        privateKeys[0] = _ownerPk;
    }

    function testUp() public {
        assertEq(_kintoWallet.owners(0), _owner);
        assertEq(_entryPoint.walletFactory(), address(_walletFactory));
    }

    /* ============ Recovery Process ============ */

    function testRecoverAccountSuccessfully() public {
        vm.startPrank(_recoverer);
        assertEq(_kintoWallet.owners(0), _owner);

        // start Recovery
        _walletFactory.startWalletRecovery(payable(address(_kintoWallet)));
        assertEq(_kintoWallet.inRecovery(), block.timestamp);
        vm.stopPrank();

        // Mint NFT to new owner and burn old
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](0);
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        sigdata = _auxCreateSignature(_kintoIDv1, _owner, _owner, 1, block.timestamp + 1000);
        _kintoIDv1.burnKYC(sigdata);
        vm.stopPrank();
        vm.startPrank(_owner);
        assertEq(_kintoIDv1.isKYC(_user), true);

        // Pass recovery time
        vm.warp(block.timestamp + _kintoWallet.RECOVERY_TIME() + 1);
        address[] memory users = new address[](1);
        users[0] = _user;
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);
        vm.stopPrank();
        vm.prank(_kycProvider);
        _kintoIDv1.monitor(users, updates);
        vm.prank(_recoverer);
        _walletFactory.completeWalletRecovery(payable(address(_kintoWallet)), users);
        assertEq(_kintoWallet.inRecovery(), 0);
        assertEq(_kintoWallet.owners(0), _user);
    }

    function test_RevertWhen_RecoverNotRecoverer(address someone) public {
        vm.assume(someone != _kintoWallet.recoverer());
        // start recovery
        vm.expectRevert("only recoverer");
        _walletFactory.startWalletRecovery(payable(address(_kintoWallet)));
    }

    function test_RevertWhen_DirectCall() public {
        vm.prank(_recoverer);
        vm.expectRevert("KW: only factory");
        _kintoWallet.startRecovery();
    }

    function test_RevertWhen_RecoverWithoutBurningOldOwner() public {
        assertEq(_kintoWallet.owners(0), _owner);

        // start recovery
        vm.prank(_recoverer);
        _walletFactory.startWalletRecovery(payable(address(_kintoWallet)));
        assertEq(_kintoWallet.inRecovery(), block.timestamp);

        // approve KYC for _user (mint NFT)
        approveKYC(_kycProvider, _user, _userPk);
        assertEq(_kintoIDv1.isKYC(_user), true);

        // pass recovery time
        vm.warp(block.timestamp + _kintoWallet.RECOVERY_TIME() + 1);

        // monitor AML
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);

        address[] memory users = new address[](1);
        users[0] = _user;

        vm.prank(_kycProvider);
        _kintoIDv1.monitor(users, updates);

        // complete recovery
        vm.prank(_recoverer);
        vm.expectRevert("KW-fr: Old KYC must be burned");
        _walletFactory.completeWalletRecovery(payable(address(_kintoWallet)), users);
    }

    function test_RevertWhen_RecoverWithoutNewOwnerKYCd() public {
        assertEq(_kintoWallet.owners(0), _owner);

        // start Recovery
        vm.prank(_recoverer);
        _walletFactory.startWalletRecovery(payable(address(_kintoWallet)));
        assertEq(_kintoWallet.inRecovery(), block.timestamp);

        // burn old owner NFT
        revokeKYC(_kycProvider, _owner, _ownerPk);
        assertEq(_kintoIDv1.isKYC(_owner), false);

        // pass recovery time
        vm.warp(block.timestamp + _kintoWallet.RECOVERY_TIME() + 1);

        // complete recovery
        assertEq(_kintoIDv1.isKYC(_user), false); // new owner is not KYC'd
        address[] memory users = new address[](1);
        users[0] = _user;
        vm.prank(_recoverer);
        vm.expectRevert("KW-rs: KYC Required");
        _walletFactory.completeWalletRecovery(payable(address(_kintoWallet)), users);
    }

    function test_RevertWhen_RecoverNotEnoughTime() public {
        assertEq(_kintoWallet.owners(0), _owner);

        // start Recovery
        vm.prank(_recoverer);
        _walletFactory.startWalletRecovery(payable(address(_kintoWallet)));
        assertEq(_kintoWallet.inRecovery(), block.timestamp);

        // burn old owner NFT
        revokeKYC(_kycProvider, _owner, _ownerPk);
        assertEq(_kintoIDv1.isKYC(_owner), false);

        // approve KYC for _user (mint NFT)
        approveKYC(_kycProvider, _user, _userPk);
        assertEq(_kintoIDv1.isKYC(_user), true);

        // pass recovery time (not enough)
        vm.warp(block.timestamp + _kintoWallet.RECOVERY_TIME() - 1);

        // monitor AML
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);

        address[] memory users = new address[](1);
        users[0] = _user;

        vm.prank(_kycProvider);
        _kintoIDv1.monitor(users, updates);

        // complete recovery
        vm.prank(_recoverer);

        vm.expectRevert("KW-fr: too early");
        _walletFactory.completeWalletRecovery(payable(address(_kintoWallet)), users);
    }
}

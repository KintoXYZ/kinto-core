// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "@aa/interfaces/IEntryPoint.sol";
import "@aa/core/EntryPoint.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/wallet/KintoWalletFactory.sol";
import "../src/KintoID.sol";
import "../src/sample/Counter.sol";
import "../src/interfaces/IKintoWallet.sol";
import "../src/wallet/KintoWallet.sol";

import "./SharedSetup.t.sol";

contract KintoWalletUpgrade is KintoWallet {
    constructor(IEntryPoint _entryPoint, IKintoID _kintoID, IKintoAppRegistry _kintoAppRegistry)
        KintoWallet(_entryPoint, _kintoID, _kintoAppRegistry)
    {}

    function walletFunction() public pure returns (uint256) {
        return 1;
    }
}

contract KintoWalletFactoryUpgrade is KintoWalletFactory {
    constructor(KintoWallet _impl) KintoWalletFactory(_impl) {}

    function newFunction() public pure returns (uint256) {
        return 1;
    }
}

contract KintoWalletFactoryTest is SharedSetup {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoWalletFactoryUpgrade _walletFactoryv2;
    KintoWalletUpgrade _kintoWalletv2;

    function testUp() public override {
        super.testUp();
        if (!fork) assertEq(_walletFactory.factoryWalletVersion(), 2);
        assertEq(_entryPoint.walletFactory(), address(_walletFactory));
    }

    /* ============ Create Account tests ============ */

    function testCreateAccount() public {
        vm.prank(address(_owner));
        _kintoWallet = _walletFactory.createAccount(_owner, _owner, 0);
        assertEq(_kintoWallet.owners(0), _owner);
    }

    function testCreateAccount_WhenAlreadyExists() public {
        vm.prank(address(_owner));
        _kintoWallet = _walletFactory.createAccount(_owner, _owner, 0);

        vm.prank(address(_owner));
        IKintoWallet _kintoWalletAfter = _walletFactory.createAccount(_owner, _owner, 0);
        assertEq(address(_kintoWallet), address(_kintoWalletAfter));
    }

    function testCreateAccount_RevertWhen_ZeroAddress() public {
        vm.prank(address(_owner));
        vm.expectRevert(IKintoWalletFactory.InvalidInput.selector);
        _kintoWallet = _walletFactory.createAccount(address(0), _owner, 0);

        vm.prank(address(_owner));
        vm.expectRevert(IKintoWalletFactory.InvalidInput.selector);
        _kintoWallet = _walletFactory.createAccount(_owner, address(0), 0);
    }

    function testCreateAccount_RevertWhen_OwnerNotKYCd() public {
        vm.prank(address(_user2));
        vm.expectRevert(IKintoWalletFactory.KYCRequired.selector);
        _kintoWallet = _walletFactory.createAccount(_user2, _owner, 0);
    }

    function testCreateAccount_RevertWhen_OwnerAndSenderMismatch() public {
        vm.prank(address(_owner));
        vm.expectRevert(IKintoWalletFactory.KYCRequired.selector);
        _kintoWallet = _walletFactory.createAccount(_user2, _owner, 0);
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        KintoWalletFactoryUpgrade _newImplementation = new KintoWalletFactoryUpgrade(_kintoWalletImpl);
        vm.prank(_owner);
        _walletFactory.upgradeTo(address(_newImplementation));
        assertEq(KintoWalletFactoryUpgrade(address(_walletFactory)).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner(address someone) public {
        vm.assume(someone != _owner);
        KintoWalletFactoryUpgrade _newImplementation = new KintoWalletFactoryUpgrade(_kintoWalletImpl);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(someone);
        _walletFactory.upgradeTo(address(_newImplementation));
    }

    function testUpgradeAllWalletImplementations() public {
        vm.startPrank(_owner);

        // Deploy a new wallet implementation
        _kintoWalletImpl =
            KintoWallet(payable(address(new KintoWalletUpgrade(_entryPoint, _kintoID, _kintoAppRegistry))));

        // deploy walletv1 through wallet factory and initializes it
        _kintoWallet = _walletFactory.createAccount(_owner, _owner, 0);

        // Upgrade all implementations
        _walletFactory.upgradeAllWalletImplementations(_kintoWalletImpl);

        KintoWalletUpgrade walletV2 = KintoWalletUpgrade(payable(address(_kintoWallet)));
        assertEq(walletV2.walletFunction(), 1);
        vm.stopPrank();
    }

    function testUpgradeAllWalletImplementations_RevertWhen_CallerIsNotOwner() public {
        // deploy a new wallet implementation
        _kintoWalletImpl = new KintoWalletUpgrade(_entryPoint, _kintoID, _kintoAppRegistry);

        // deploy walletv1 through wallet factory and initializes it
        vm.broadcast(_owner);
        _kintoWallet = _walletFactory.createAccount(_owner, _owner, 0);

        // upgrade all implementations
        vm.expectRevert("Ownable: caller is not the owner");
        _walletFactory.upgradeAllWalletImplementations(_kintoWalletImpl);
    }

    function testUpgradeAllWalletImplementations_RevertWhen_ZeroAddress() public {
        vm.prank(_owner);
        vm.expectRevert(IKintoWalletFactory.InvalidImplementation.selector);
        _walletFactory.upgradeAllWalletImplementations(IKintoWallet(address(0)));
    }

    function testUpgradeAllWalletImplementations_RevertWhen_BeaconAddress() public {
        IKintoWallet _newImpl = IKintoWallet(UpgradeableBeacon(_walletFactory.beacon()).implementation());
        vm.prank(_owner);
        vm.expectRevert(IKintoWalletFactory.InvalidImplementation.selector);
        _walletFactory.upgradeAllWalletImplementations(_newImpl);
    }

    /* ============ Deploy tests ============ */

    function testDeployContract() public {
        address computed =
            _walletFactory.getContractAddress(bytes32(0), keccak256(abi.encodePacked(type(Counter).creationCode)));

        vm.prank(_owner);
        address created =
            _walletFactory.deployContract(_owner, 0, abi.encodePacked(type(Counter).creationCode), bytes32(0));

        assertEq(computed, created);
        assertEq(Counter(created).count(), 0);

        Counter(created).increment();
        assertEq(Counter(created).count(), 1);
    }

    function testDeployContract_RevertWhen_SenderNotKYCd() public {
        vm.prank(_user2);
        vm.expectRevert(IKintoWalletFactory.KYCRequired.selector);
        _walletFactory.deployContract(_owner, 0, abi.encodePacked(type(Counter).creationCode), bytes32(0));
    }

    function testDeployContract_RevertWhen_AmountMismatch() public {
        vm.deal(_owner, 1 ether);
        vm.prank(_owner);
        vm.expectRevert(IKintoWalletFactory.AmountMismatch.selector);
        _walletFactory.deployContract(_owner, 1 ether + 1, abi.encodePacked(type(Counter).creationCode), bytes32(0));
    }

    function testDeployContract_RevertWhen_ZeroBytecode() public {
        vm.expectRevert(IKintoWalletFactory.EmptyBytecode.selector);
        vm.prank(_owner);
        _walletFactory.deployContract(_owner, 0, bytes(""), bytes32(0));
    }

    function testDeployContract_RevertWhen_CreateWallet() public {
        bytes memory initialize = abi.encodeWithSelector(
            IKintoWallet.initialize.selector,
            fork ? vm.envAddress("DEPLOYER_PUBLIC_KEY") : _owner,
            fork ? vm.envAddress("LEDGER_ADMIN") : _owner
        );
        bytes memory bytecode = abi.encodePacked(
            type(SafeBeaconProxy).creationCode, abi.encode(address(_walletFactory.beacon()), initialize)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IKintoWalletFactory.DeploymentNotAllowed.selector, "Direct KintoWallet deployment not allowed"
            )
        );
        vm.prank(_owner);
        _walletFactory.deployContract(_owner, 0, bytecode, bytes32(0));
    }

    function testFundWallet() public {
        uint256 previousBalance = address(_kintoWallet).balance;
        vm.prank(_owner);
        _walletFactory.fundWallet{value: 1 ether}(payable(address(_kintoWallet)));
        assertEq(address(_kintoWallet).balance, previousBalance + 1 ether);
    }

    function testFundWallet_WhenCallerIsWhitelisted() public {
        uint256 previousBalance = address(_kintoWallet).balance;

        address[] memory funders = new address[](1);
        funders[0] = _funder;

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

        vm.deal(_funder, 1e17);
        vm.prank(_funder);
        _walletFactory.fundWallet{value: 1e17}(payable(address(_kintoWallet)));
        assertEq(address(_kintoWallet).balance, previousBalance + 1e17);
    }

    function testFundWallet_RevertWhen_InvalidWallet() public {
        vm.expectRevert(IKintoWalletFactory.InvalidWalletOrFunder.selector);
        vm.prank(_owner);
        _walletFactory.fundWallet{value: 1e18}(payable(address(0)));
    }

    function testFundWallet_RevertWhen_CallerIsInvalid() public {
        vm.deal(_user, 1 ether);
        vm.expectRevert(IKintoWalletFactory.InvalidWalletOrFunder.selector);
        vm.prank(_user);
        _walletFactory.fundWallet{value: 1 ether}(payable(address(_kintoWallet)));
    }

    function testFundWallet_RevertWhen_NotEnoughETH() public {
        vm.expectRevert(IKintoWalletFactory.InvalidWalletOrFunder.selector);
        vm.prank(_owner);
        _walletFactory.fundWallet{value: 0}(payable(address(_kintoWallet)));
    }

    /* ============ Recovery tests ============ */

    function testStartWalletRecovery_WhenCallerIsRecoverer() public {
        vm.prank(address(_kintoWallet.recoverer()));
        _walletFactory.startWalletRecovery(payable(address(_kintoWallet)));
    }

    function testStartWalletRecovery_WhenCallerIsRecoverer_RevertWhen_WalletNotExists() public {
        vm.prank(address(_kintoWallet.recoverer()));
        vm.expectRevert(IKintoWalletFactory.InvalidWallet.selector);
        _walletFactory.startWalletRecovery(payable(address(123)));
    }

    function testStartWalletRecovery_RevertWhen_CallerIsNotRecoverer(address someone) public {
        vm.assume(someone != address(_kintoWallet.recoverer()));
        vm.prank(someone);
        vm.expectRevert(IKintoWalletFactory.OnlyRecoverer.selector);
        _walletFactory.startWalletRecovery(payable(address(_kintoWallet)));
    }

    function testCompleteWalletRecovery_RevertWhen_CallerIsRecovererAndAlreadyKYC() public {
        vm.prank(address(_kintoWallet.recoverer()));
        _walletFactory.startWalletRecovery(payable(address(_kintoWallet)));

        vm.warp(block.timestamp + _kintoWallet.RECOVERY_TIME() + 1);

        approveKYC(_kycProvider, _user, _userPk);

        // run monitor
        address[] memory users = new address[](1);
        users[0] = _user;
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);
        vm.prank(_kycProvider);
        _kintoID.monitor(users, updates);

        vm.prank(address(_kintoWallet.recoverer()));
        vm.expectRevert(IKintoWalletFactory.KYCMustNotExist.selector);
        _walletFactory.completeWalletRecovery(payable(address(_kintoWallet)), users);
    }

    function testCompleteWalletRecovery_RevertWhenCallerIsRecovererButOwnerBurnedID() public {
        vm.prank(address(_kintoWallet.recoverer()));
        _walletFactory.startWalletRecovery(payable(address(_kintoWallet)));

        vm.warp(block.timestamp + _kintoWallet.RECOVERY_TIME() + 1);

        revokeKYC(_kycProvider, _owner, _ownerPk);

        // run monitor
        address[] memory users = new address[](1);
        users[0] = _noKyc;
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);
        vm.prank(_kycProvider);
        _kintoID.monitor(users, updates);

        vm.prank(address(_kintoWallet.recoverer()));
        vm.expectRevert("Invalid transfer");
        _walletFactory.completeWalletRecovery(payable(address(_kintoWallet)), users);
    }

    function testCompleteWalletRecovery_WhenCallerIsRecoverer() public {
        vm.prank(address(_kintoWallet.recoverer()));
        _walletFactory.startWalletRecovery(payable(address(_kintoWallet)));

        vm.warp(block.timestamp + _kintoWallet.RECOVERY_TIME() + 1);

        // run monitor
        address[] memory users = new address[](1);
        users[0] = _noKyc;
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);
        vm.prank(_kycProvider);
        _kintoID.monitor(users, updates);

        vm.prank(address(_kintoWallet.recoverer()));
        _walletFactory.completeWalletRecovery(payable(address(_kintoWallet)), users);
    }

    function testCompleteWalletRecovery_RevertWhen_WhenCallerIsRecoverer_WalletNotExists() public {
        vm.prank(address(_kintoWallet.recoverer()));
        vm.expectRevert(IKintoWalletFactory.InvalidWallet.selector);
        _walletFactory.completeWalletRecovery(payable(address(123)), new address[](0));
    }

    function testCompleteWalletRecovery_RevertWhen_CallerIsNotRecoverer(address someone) public {
        vm.assume(someone != address(_kintoWallet.recoverer()));
        vm.prank(someone);
        vm.expectRevert(IKintoWalletFactory.OnlyRecoverer.selector);
        _walletFactory.completeWalletRecovery(payable(address(_kintoWallet)), new address[](0));
    }

    function testChangeWalletRecoverer_WhenCallerIsRecoverer() public {
        vm.prank(address(_kintoWallet.recoverer()));
        _walletFactory.changeWalletRecoverer(payable(address(_kintoWallet)), payable(address(123)));
    }

    function testChangeWalletRecoverer_RevertWhen_CallerIsRecoverer_WhenWalletNotExists() public {
        vm.prank(address(_kintoWallet.recoverer()));
        vm.expectRevert(IKintoWalletFactory.InvalidWallet.selector);
        _walletFactory.changeWalletRecoverer(payable(address(123)), payable(address(123)));
    }

    function testChangeWalletRecoverer_RevertWhen_CallerIsNotRecoverer(address someone) public {
        vm.assume(someone != address(_kintoWallet.recoverer()));
        vm.prank(someone);
        vm.expectRevert(IKintoWalletFactory.OnlyRecoverer.selector);
        _walletFactory.changeWalletRecoverer(payable(address(_kintoWallet)), payable(address(123)));
    }

    /* ============ Send Money tests ============ */

    function testSendMoneyToAccount_WhenCallerIsKYCd() public {
        approveKYC(_kycProvider, _user, _userPk);
        approveKYC(_kycProvider, _user2, _user2Pk);

        vm.deal(_user, 1 ether);
        vm.prank(_user);
        _walletFactory.sendMoneyToAccount{value: 1e18}(address(_user2));
        assertEq(address(_user2).balance, 1e18);
    }

    function testSendMoneyToAccount_WhenCallerIsKYCdAndTargetIsContract() public {
        uint256 previousBalance = address(_kintoWallet).balance;
        approveKYC(_kycProvider, _user, _userPk);
        vm.deal(_user, 1 ether);
        vm.prank(_user);
        _walletFactory.sendMoneyToAccount{value: 1 ether}(address(_kintoWallet));
        assertEq(address(_kintoWallet).balance, previousBalance + 1 ether);
    }

    function testSendMoneyToAccount_WhenCallerIsOwner() public {
        revokeKYC(_kycProvider, _owner, _ownerPk);
        vm.prank(_owner);
        _walletFactory.sendMoneyToAccount{value: 1e18}(address(123));
        assertEq(address(123).balance, 1e18);
    }

    function testSendMoneyToAccount_WhenCallerIsOwner_WhenTargetIsKYC() public {
        approveKYC(_kycProvider, _user, _userPk);
        revokeKYC(_kycProvider, _owner, _ownerPk);
        vm.prank(_owner);
        _walletFactory.sendMoneyToAccount{value: 1e18}(address(_user));
        assertEq(address(_user).balance, 1e18);
    }

    function testSendMoneyToAccount_WhenCallerIsKYCProvider_WhenTargetKYCProvider() public {
        // make sure target is not KYC'd
        assertFalse(_kintoID.isKYC(_user2));

        // grant kyc provider role to _user2
        bytes32 role = _kintoID.KYC_PROVIDER_ROLE();
        vm.prank(_owner);
        _kintoID.grantRole(role, _user2);

        // top up _user2
        vm.deal(_kycProvider, 1e18);

        // send money from _kycProvider to _user2
        vm.prank(_kycProvider);
        _walletFactory.sendMoneyToAccount{value: 1e18}(address(_user2));
        assertEq(address(_user2).balance, 1e18);
    }

    function testSendMoneyToAccount_WhenCallerIsOwner_WhenTargetKYCProvider() public {
        // make sure target is not KYC'd
        assertFalse(_kintoID.isKYC(_kycProvider));

        // send money from _owner to _kycProvider
        vm.prank(_owner);
        _walletFactory.sendMoneyToAccount{value: 1e18}(address(_kycProvider));
        assertEq(address(_kycProvider).balance, 1e18);
    }

    function testSendMoneyToAccount_WhenCallerIsKYCProvider() public {
        vm.deal(_kycProvider, 1 ether);
        vm.prank(_kycProvider);
        _walletFactory.sendMoneyToAccount{value: 1e18}(address(123));
        assertEq(address(123).balance, 1e18);
    }

    function testSendMoneyToAccount_WhenCallerIsOwner_WhenAccountIsWallet() public {
        uint256 previousBalance = address(_kintoWallet).balance;
        vm.prank(_owner);
        _walletFactory.sendMoneyToAccount{value: 1 ether}(address(_kintoWallet));
        assertEq(address(_kintoWallet).balance, previousBalance + 1 ether);
    }

    function testSendMoneyToAccount_WhenCallerIsOwner_WhenAccountIsEOA() public {
        vm.prank(_owner);
        _walletFactory.sendMoneyToAccount{value: 1e18}(address(123));
        assertEq(address(123).balance, 1e18);
    }

    function testSendMoneyToAccount_WhenCallerIsKYCd_WhenTargetIsContract() public {
        vm.deal(_kycProvider, 1 ether);
        vm.prank(_kycProvider);
        uint256 beforeBalance = address(_kintoWallet).balance;
        _walletFactory.sendMoneyToAccount{value: 1e18}(address(_kintoWallet));
        assertEq(address(_kintoWallet).balance, beforeBalance + 1e18);
    }

    function testSendMoneyToAccount_RevertWhen_CallerIsNotAllowed() public {
        vm.deal(address(123), 1 ether);
        vm.prank(address(123));
        vm.expectRevert(IKintoWalletFactory.OnlyPrivileged.selector);
        _walletFactory.sendMoneyToAccount{value: 1e18}(address(123));
    }

    function testSendMoneyToAccount_RevertWhen_CallerIsKYCd_WhenTargetisNotKYCd() public {
        approveKYC(_kycProvider, _user, _userPk);
        vm.deal(_user, 1 ether);
        vm.prank(_user);
        vm.expectRevert(IKintoWalletFactory.InvalidTarget.selector);
        _walletFactory.sendMoneyToAccount{value: 1e18}(address(123));
    }

    /* ============ Claim From Faucet tests ============ */

    function testClaimFromFaucet_WhenCallerIsKYCd() public {
        vm.prank(_owner);
        _faucet.startFaucet{value: 1 ether}();

        IFaucet.SignatureData memory sigdata = _auxCreateSignature(_faucet, _user, _userPk, block.timestamp + 1000);
        vm.prank(_kycProvider);
        _walletFactory.claimFromFaucet(address(_faucet), sigdata);
        assertEq(_user.balance, _faucet.CLAIM_AMOUNT());
    }

    function testClaimFromFaucet_RevertWhen_CallerIsNotKYCd() public {
        vm.prank(_owner);
        _faucet.startFaucet{value: 1 ether}();

        IFaucet.SignatureData memory sigdata = _auxCreateSignature(_faucet, _user, _userPk, block.timestamp + 1000);
        vm.expectRevert(IKintoWalletFactory.InvalidSender.selector);
        _walletFactory.claimFromFaucet(address(_faucet), sigdata);
    }

    function testClaimFromFaucet_RevertWhen_FaucetIsZeroAddress() public {
        vm.prank(_owner);
        _faucet.startFaucet{value: 1 ether}();

        IFaucet.SignatureData memory sigdata = _auxCreateSignature(_faucet, _user, _userPk, block.timestamp + 1000);
        vm.expectRevert(IKintoWalletFactory.InvalidFaucet.selector);
        vm.prank(_kycProvider);
        _walletFactory.claimFromFaucet(address(0), sigdata);
    }
}

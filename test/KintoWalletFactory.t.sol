// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "@aa/interfaces/IEntryPoint.sol";
import "@aa/core/EntryPoint.sol";

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
        assertEq(_walletFactory.factoryWalletVersion(), 2);
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

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        vm.startPrank(_owner);
        KintoWalletFactoryUpgrade _newImplementation = new KintoWalletFactoryUpgrade(_kintoWalletImpl);
        _walletFactory.upgradeTo(address(_newImplementation));
        // re-wrap the _proxy
        _walletFactoryv2 = KintoWalletFactoryUpgrade(address(_walletFactory));
        assertEq(_walletFactoryv2.newFunction(), 1);
        vm.stopPrank();
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner(address someone) public {
        vm.assume(someone != _owner);
        KintoWalletFactoryUpgrade _newImplementation = new KintoWalletFactoryUpgrade(_kintoWalletImpl);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(someone);
        _walletFactory.upgradeTo(address(_newImplementation));
    }

    function testAllWalletsUpgrade() public {
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

    function testUpgrade_RevertWhen_CallerIsNotOwner() public {
        // deploy a new wallet implementation
        _kintoWalletImpl = new KintoWalletUpgrade(_entryPoint, _kintoID, _kintoAppRegistry);

        // deploy walletv1 through wallet factory and initializes it
        vm.broadcast(_owner);
        _kintoWallet = _walletFactory.createAccount(_owner, _owner, 0);

        // upgrade all implementations
        vm.expectRevert("Ownable: caller is not the owner");
        _walletFactory.upgradeAllWalletImplementations(_kintoWalletImpl);
    }

    /* ============ Deploy tests ============ */

    function testDeployCustomContract() public {
        vm.startPrank(_owner);
        address computed =
            _walletFactory.getContractAddress(bytes32(0), keccak256(abi.encodePacked(type(Counter).creationCode)));
        address created =
            _walletFactory.deployContract(_owner, 0, abi.encodePacked(type(Counter).creationCode), bytes32(0));
        assertEq(computed, created);
        assertEq(Counter(created).count(), 0);
        Counter(created).increment();
        assertEq(Counter(created).count(), 1);
        vm.stopPrank();
    }

    function testDeploy_RevertWhen_CreateWalletThroughDeploy() public {
        vm.startPrank(_owner);
        bytes memory initialize = abi.encodeWithSelector(IKintoWallet.initialize.selector, _owner, _owner);
        bytes memory bytecode = abi.encodePacked(
            type(SafeBeaconProxy).creationCode, abi.encode(address(_walletFactory.beacon()), initialize)
        );
        vm.expectRevert("Direct KintoWallet deployment not allowed");
        _walletFactory.deployContract(_owner, 0, bytecode, bytes32(0));
        vm.stopPrank();
    }

    function testSignerCanFundWallet() public {
        vm.startPrank(_owner);
        _walletFactory.fundWallet{value: 1e18}(payable(address(_kintoWallet)));
        assertEq(address(_kintoWallet).balance, 1e18);
    }

    function testWhitelistedSignerCanFundWallet() public {
        vm.startPrank(_owner);
        fundSponsorForApp(address(_kintoWallet));
        uint256 nonce = _kintoWallet.getNonce();
        address[] memory funders = new address[](1);
        funders[0] = _funder;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            nonce,
            privateKeys,
            abi.encodeWithSignature("setFunderWhitelist(address[],bool[])", funders, flags),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        _entryPoint.handleOps(userOps, payable(_owner));
        vm.deal(_funder, 1e17);
        vm.startPrank(_funder);
        _walletFactory.fundWallet{value: 1e17}(payable(address(_kintoWallet)));
        assertEq(address(_kintoWallet).balance, 1e17);
    }

    function testSignerCannotFundInvalidWallet() public {
        vm.startPrank(_owner);
        vm.expectRevert("Invalid wallet or funder");
        _walletFactory.fundWallet{value: 1e18}(payable(address(0)));
    }

    function testRandomSignerCannotFundWallet() public {
        vm.deal(_user, 1e18);
        vm.startPrank(_user);
        vm.expectRevert("Invalid wallet or funder");
        _walletFactory.fundWallet{value: 1e18}(payable(address(_kintoWallet)));
    }

    function testSignerCannotFundWalletWithoutEth() public {
        vm.startPrank(_owner);
        vm.expectRevert("Invalid wallet or funder");
        _walletFactory.fundWallet{value: 0}(payable(address(_kintoWallet)));
    }

    /* ============ Recovery tests ============ */

    function testStartWalletRecovery_WhenCallerIsRecoverer() public {
        vm.prank(address(_kintoWallet.recoverer()));
        _walletFactory.startWalletRecovery(payable(address(_kintoWallet)));
    }

    function testStartWalletRecovery_WhenCallerIsRecoverer_RevertWhen_WalletNotExists() public {
        vm.prank(address(_kintoWallet.recoverer()));
        vm.expectRevert("invalid wallet");
        _walletFactory.startWalletRecovery(payable(address(123)));
    }

    function testStartWalletRecovery_RevertWhen_CallerIsNotRecoverer(address someone) public {
        vm.assume(someone != address(_kintoWallet.recoverer()));
        vm.prank(someone);
        vm.expectRevert("only recoverer");
        _walletFactory.startWalletRecovery(payable(address(_kintoWallet)));
    }

    function testCompleteWalletRecovery_WhenCallerIsRecoverer() public {
        vm.prank(address(_kintoWallet.recoverer()));
        _walletFactory.startWalletRecovery(payable(address(_kintoWallet)));

        vm.warp(block.timestamp + _kintoWallet.RECOVERY_TIME() + 1);

        // approve KYC for _user burn KYC for _owner
        revokeKYC(_kycProvider, _owner, _ownerPk);
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
        _walletFactory.completeWalletRecovery(payable(address(_kintoWallet)), users);
    }

    function testCompleteWalletRecovery_RevertWhen_WhenCallerIsRecoverer_WalletNotExists() public {
        vm.prank(address(_kintoWallet.recoverer()));
        vm.expectRevert("invalid wallet");
        _walletFactory.completeWalletRecovery(payable(address(123)), new address[](0));
    }

    function testCompleteWalletRecovery_RevertWhen_CallerIsNotRecoverer(address someone) public {
        vm.assume(someone != address(_kintoWallet.recoverer()));
        vm.prank(someone);
        vm.expectRevert("only recoverer");
        _walletFactory.completeWalletRecovery(payable(address(_kintoWallet)), new address[](0));
    }

    function testChangeWalletRecoverer_WhenCallerIsRecoverer() public {
        vm.prank(address(_kintoWallet.recoverer()));
        _walletFactory.changeWalletRecoverer(payable(address(_kintoWallet)), payable(address(123)));
    }

    function testChangeWalletRecoverer_RevertWhen_CallerIsRecoverer_WhenWalletNotExists() public {
        vm.prank(address(_kintoWallet.recoverer()));
        vm.expectRevert("invalid wallet");
        _walletFactory.changeWalletRecoverer(payable(address(123)), payable(address(123)));
    }

    function testChangeWalletRecoverer_RevertWhen_CallerIsNotRecoverer(address someone) public {
        vm.assume(someone != address(_kintoWallet.recoverer()));
        vm.prank(someone);
        vm.expectRevert("only recoverer");
        _walletFactory.changeWalletRecoverer(payable(address(_kintoWallet)), payable(address(123)));
    }

    /* ============ Send Money tests ============ */

    function testSendMoneyToAccount_WhenCallerIsKYCd() public {
        approveKYC(_kycProvider, _user, _userPk);
        vm.deal(_user, 1 ether);
        vm.prank(_user);
        _walletFactory.sendMoneyToAccount{value: 1e18}(address(123));
        assertEq(address(123).balance, 1e18);
    }

    function testSendMoneyToAccount_WhenCallerIsOwner() public {
        revokeKYC(_kycProvider, _owner, _ownerPk);
        vm.prank(_owner);
        _walletFactory.sendMoneyToAccount{value: 1e18}(address(123));
        assertEq(address(123).balance, 1e18);
    }

    function testSendMoneyToAccount_WhenCallerIsKYCProvider() public {
        vm.deal(_kycProvider, 1 ether);
        vm.prank(_kycProvider);
        _walletFactory.sendMoneyToAccount{value: 1e18}(address(123));
        assertEq(address(123).balance, 1e18);
    }

    function testSendMoneyToAccount_WhenCallerIsOwner_WhenAccountIsWallet() public {
        vm.prank(_owner);
        _walletFactory.sendMoneyToAccount{value: 1e18}(address(_kintoWallet));
        assertEq(address(_kintoWallet).balance, 1e18);
    }

    function testSendMoneyToAccount_WhenCallerIsOwner_WhenAccountIsEOA() public {
        vm.prank(_owner);
        _walletFactory.sendMoneyToAccount{value: 1e18}(address(123));
        assertEq(address(123).balance, 1e18);
    }

    function testSendMoneyToAccount_RevertWhen_CallerIsNotAllowed() public {
        vm.deal(address(123), 1 ether);
        vm.prank(address(123));
        vm.expectRevert("KYC or Provider role required");
        _walletFactory.sendMoneyToAccount{value: 1e18}(address(123));
    }
}

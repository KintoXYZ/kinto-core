// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '../src/wallet/KintoWallet.sol';
import '../src/wallet/KintoWalletFactory.sol';
import '../src/paymasters/SponsorPaymaster.sol';
import '../src/KintoID.sol';
import {UserOp} from './helpers/UserOp.sol';
import {UUPSProxy} from './helpers/UUPSProxy.sol';
import {KYCSignature} from './helpers/KYCSignature.sol';

import '@aa/interfaces/IAccount.sol';
import '@aa/interfaces/INonceManager.sol';
import '@aa/interfaces/IEntryPoint.sol';
import '@aa/core/EntryPoint.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
import { UpgradeableBeacon } from '@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol';
import {SignatureChecker} from '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';

import 'forge-std/Test.sol';
import 'forge-std/console.sol';

contract KintoWalletv2 is KintoWallet {
  constructor(IEntryPoint _entryPoint, IKintoID _kintoID) KintoWallet(_entryPoint, _kintoID) {}

  function newFunction() public pure returns (uint256) {
      return 1;
  }
}

contract Counter {

    uint256 public count;

    constructor() {
      count = 0;
    }

    function increment() public {
        count += 1;
    }
}

contract KintoWalletTest is UserOp, KYCSignature {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    EntryPoint _entryPoint;
    KintoWalletFactory _walletFactoryI;
    KintoWalletFactory _walletFactory;
    KintoID _implementation;
    KintoID _kintoIDv1;
    SponsorPaymaster _paymaster;

    KintoWallet _kintoWalletImpl;
    IKintoWallet _kintoWalletv1;
    KintoWalletv2 _kintoWalletv2;
    UUPSProxy _proxy;
    UUPSProxy _proxyf;
    UUPSProxy _proxys;
    UpgradeableBeacon _beacon;

    uint256 _chainID = 1;

    address payable _owner = payable(vm.addr(1));
    address _secondowner = address(2);
    address _user = vm.addr(3);
    address _user2 = address(4);
    address _upgrader = address(5);
    address _kycProvider = address(6);
    address _recoverer = address(7);


    function setUp() public {
        vm.chainId(_chainID);
        vm.startPrank(address(1));
        _owner.transfer(1e18);
        vm.stopPrank();
        vm.startPrank(_owner);
        // Deploy Kinto ID
        _implementation = new KintoID();
        // deploy _proxy contract and point it to _implementation
        _proxy = new UUPSProxy(address(_implementation), '');
        // wrap in ABI to support easier calls
        _kintoIDv1 = KintoID(address(_proxy));
        // Initialize _proxy
        _kintoIDv1.initialize();
        _kintoIDv1.grantRole(_kintoIDv1.KYC_PROVIDER_ROLE(), _kycProvider);
        _entryPoint = new EntryPoint{salt: 0}();
        // Deploy wallet implementation
        _kintoWalletImpl = new KintoWallet(_entryPoint, _kintoIDv1);
        // Deploy beacon
        _beacon = new UpgradeableBeacon(address(_kintoWalletImpl));
        //Deploy wallet factory implementation
        _walletFactoryI = new KintoWalletFactory(_beacon);
        _proxyf = new UUPSProxy(address(_walletFactoryI), '');
        _walletFactory = KintoWalletFactory(address(_proxyf));
        _walletFactory.initialize(_kintoIDv1);
        // Set the wallet factory in the entry point
        _entryPoint.setWalletFactory(address(_walletFactory));
        // Mint an nft to the owner
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(
            _kintoIDv1, _owner, _owner, 1, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](0);
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        vm.stopPrank();
        vm.startPrank(_owner);
        // deploy walletv1 through wallet factory and initializes it
        _kintoWalletv1 = _walletFactory.createAccount(_owner, _recoverer, 0);
        console.log('wallet address ', address(_kintoWalletv1));
        // deploy the paymaster
        _paymaster = new SponsorPaymaster(_entryPoint);
        // deploy _proxy contract and point it to _implementation
        _proxys = new UUPSProxy(address(_paymaster), '');
        // wrap in ABI to support easier calls
        _paymaster = SponsorPaymaster(address(_proxys));
        // Initialize proxy
        _paymaster.initialize(_owner);
        vm.stopPrank();
    }

    function testUp() public {
        assertEq(address(_kintoWalletv1.factory()), address(_walletFactory));
        assertEq(_kintoWalletv1.owners(0), _owner);
    }

    /* ============ Upgrade Tests ============ */

    // TODO: test factory can upgrade

    function testFailOwnerCannotUpgrade() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        KintoWalletv2 _implementationV2 = new KintoWalletv2(_entryPoint, _kintoIDv1);
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce, privateKeys,
            address(_kintoWalletv1), 0,
            abi.encodeWithSignature('upgradeTo(address)',
            address(_implementationV2)), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        _kintoWalletv2 = KintoWalletv2(payable(address(_kintoWalletv1)));
        assertEq(_kintoWalletv2.newFunction(), 1);
        vm.stopPrank();
    }

    function testFailOthersCannotUpgrade() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        KintoWalletv2 _implementationV2 = new KintoWalletv2(_entryPoint, _kintoIDv1);
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 3;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_user), startingNonce, privateKeys,
            address(_kintoWalletv1), 0,
            abi.encodeWithSignature('upgradeTo(address)',
            address(_implementationV2)), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        _kintoWalletv2 = KintoWalletv2(payable(address(_kintoWalletv1)));
        assertEq(_kintoWalletv2.newFunction(), 1);
        vm.stopPrank();
    }

    /* ============ One Signer Account Transaction Tests ============ */

    function testFailSendingTransactionDirectly() public {
        vm.startPrank(_owner);
        // Let's deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        // Let's send a transaction to the counter contract through our wallet
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperation(
            _chainID,
            address(_kintoWalletv1), startingNonce, privateKeys, address(counter), 0,
            abi.encodeWithSignature('increment()'));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }

    function testTransactionViaPaymaster() public {
        vm.startPrank(_owner);
        // Let's deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        vm.stopPrank();
        _setPaymasterForContract(address(counter));
        vm.startPrank(_owner);
        // Let's send a transaction to the counter contract through our wallet
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce, privateKeys, address(counter), 0,
            abi.encodeWithSignature('increment()'), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }

    function testMultipleTransactionsViaPaymaster() public {
        vm.startPrank(_owner);
        // Let's deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        vm.stopPrank();
        _setPaymasterForContract(address(counter));
        vm.startPrank(_owner);
        // Let's send a transaction to the counter contract through our wallet
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce, privateKeys, address(counter), 0,
            abi.encodeWithSignature('increment()'), address(_paymaster));
        UserOperation memory userOp2 = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce + 1, privateKeys, address(counter), 0,
            abi.encodeWithSignature('increment()'), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = userOp;
        userOps[1] = userOp2;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 2);
        vm.stopPrank();
    }

    /* ============ Signers & Policy Tests ============ */

    function testAddingOneSigner() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce, privateKeys, address(_kintoWalletv1), 0,
            abi.encodeWithSignature('resetSigners(address[])',owners), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user);
        vm.stopPrank();
    }

    function testFailWithDuplicateSigner() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _owner;
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce, privateKeys, address(_kintoWalletv1),
            0, abi.encodeWithSignature('resetSigners(address[])',owners), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _owner);
        vm.stopPrank();
    }

     function testFailWithEmptyArray() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        address[] memory owners = new address[](0);
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce, privateKeys, address(_kintoWalletv1),
            0, abi.encodeWithSignature('resetSigners(address[])',owners), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(0), address(0));
        vm.stopPrank();
    }

     function testFailWithManyOwners() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        address[] memory owners = new address[](4);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user;
        owners[3] = _user;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce, privateKeys, address(_kintoWalletv1), 0,
            abi.encodeWithSignature('resetSigners(address[])',owners), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(3), _user);
        vm.stopPrank();
    }

    function testFailWithoutKYCSigner() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        address[] memory owners = new address[](1);
        owners[0] = _user;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce, privateKeys, address(_kintoWalletv1), 0,
            abi.encodeWithSignature('resetSigners(address[])',owners), address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user);
        vm.stopPrank();
    }

    function testChangingPolicyWithTwoSigners() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce, privateKeys, address(_kintoWalletv1), 0,
            abi.encodeWithSignature('resetSigners(address[])',owners), address(_paymaster));
        UserOperation memory userOp2 = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce + 1, privateKeys, address(_kintoWalletv1), 0,
            abi.encodeWithSignature('setSignerPolicy(uint8)', _kintoWalletv1.ALL_SIGNERS()),
            address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = userOp;
        userOps[1] = userOp2;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user);
        assertEq(_kintoWalletv1.signerPolicy(), _kintoWalletv1.ALL_SIGNERS());
        vm.stopPrank();
    }

    function testChangingPolicyWithThreeSigners() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        address[] memory owners = new address[](3);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user2;
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce, privateKeys, address(_kintoWalletv1), 0,
            abi.encodeWithSignature('resetSigners(address[])',owners), address(_paymaster));
        UserOperation memory userOp2 = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce + 1, privateKeys, address(_kintoWalletv1), 0,
            abi.encodeWithSignature('setSignerPolicy(uint8)', _kintoWalletv1.MINUS_ONE_SIGNER()),
            address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = userOp;
        userOps[1] = userOp2;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user);
        assertEq(_kintoWalletv1.owners(2), _user2);
        assertEq(_kintoWalletv1.signerPolicy(), _kintoWalletv1.MINUS_ONE_SIGNER());
        vm.stopPrank();
    }

    function testFailChangingPolicyWithoutRightSigners() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce, privateKeys, address(_kintoWalletv1), 0,
            abi.encodeWithSignature('resetSigners(address[])',owners), address(_paymaster));
        UserOperation memory userOp2 = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce + 1, privateKeys, address(_kintoWalletv1), 0,
            abi.encodeWithSignature('setSignerPolicy(uint8)', _kintoWalletv1.ALL_SIGNERS()),
            address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = userOp2;
        userOps[1] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user);
        assertEq(_kintoWalletv1.signerPolicy(), _kintoWalletv1.ALL_SIGNERS());
        vm.stopPrank();
    }

    /* ============ Multisig Transactions ============ */

    function testMultisigTransaction() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce, privateKeys, address(_kintoWalletv1), 0,
            abi.encodeWithSignature('resetSigners(address[])',owners), address(_paymaster));
        UserOperation memory userOp2 = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce + 1, privateKeys, address(_kintoWalletv1), 0,
            abi.encodeWithSignature('setSignerPolicy(uint8)', _kintoWalletv1.ALL_SIGNERS()),
            address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = userOp;
        userOps[1] = userOp2;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user);
        assertEq(_kintoWalletv1.signerPolicy(), _kintoWalletv1.ALL_SIGNERS());
        // Deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        vm.stopPrank();
        // Fund counter contract
        _setPaymasterForContract(address(counter));
        vm.startPrank(_owner);
        // Create counter increment transaction
        userOps = new UserOperation[](1);
        privateKeys = new uint256[](2);
        privateKeys[0] = 1;
        privateKeys[1] = 3;
        userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), _kintoWalletv1.getNonce(), privateKeys, address(counter), 0,
            abi.encodeWithSignature('increment()'), address(_paymaster));
        userOps[0] = userOp;
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }

    function testFailMultisigTransaction() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        uint startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce, privateKeys, address(_kintoWalletv1), 0,
            abi.encodeWithSignature('resetSigners(address[])',owners), address(_paymaster));
        UserOperation memory userOp2 = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), startingNonce + 1, privateKeys, address(_kintoWalletv1), 0,
            abi.encodeWithSignature('setSignerPolicy(uint8)', _kintoWalletv1.ALL_SIGNERS()),
            address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = userOp;
        userOps[1] = userOp2;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user);
        assertEq(_kintoWalletv1.signerPolicy(), _kintoWalletv1.ALL_SIGNERS());
        // Deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        vm.stopPrank();
        // Fund counter contract
        _setPaymasterForContract(address(counter));
        vm.startPrank(_owner);
        // Create counter increment transaction
        userOps = new UserOperation[](1);
        privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1), _kintoWalletv1.getNonce(), privateKeys, address(counter), 0,
            abi.encodeWithSignature('increment()'), address(_paymaster));
        userOps[0] = userOp;
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }

    // TODO: test a multisig transaction with 3 signers
    // TODO: test fail multisig transaction that requires 3 signers with 2 signers

    /* ============ Recovery Process ============ */

    function testRecoverAccountSuccessfully() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_recoverer);
        assertEq(_kintoWalletv1.owners(0), _owner);

        // Start Recovery
        _kintoWalletv1.startRecovery();
        assertEq(_kintoWalletv1.inRecovery(), block.timestamp);
        vm.stopPrank();

        // Mint NFT to new owner and burn old
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(
            _kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](0);
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        sigdata = _auxCreateSignature(_kintoIDv1, _owner, _owner, 1, block.timestamp + 1000);
        _kintoIDv1.burnKYC(sigdata);
        vm.stopPrank();
        vm.startPrank(_owner);
        assertEq(_kintoIDv1.isKYC(_user), true);
        // Pass recovery time
        vm.warp(block.timestamp + _kintoWalletv1.RECOVERY_TIME() + 1);
        address[] memory users = new address[](1);
        users[0] = _user;
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);
        vm.stopPrank();
        vm.prank(_kycProvider);
        _kintoIDv1.monitor(users, updates);
        vm.prank(_recoverer);
        _kintoWalletv1.finishRecovery(users);
        assertEq(_kintoWalletv1.inRecovery(), 0);
        assertEq(_kintoWalletv1.owners(0), _user);
    }

    function testFailRecoverNotRecoverer() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        assertEq(_kintoWalletv1.owners(0), _owner);

        // Start Recovery
        _kintoWalletv1.startRecovery();
    }

    function testFailRecoverWithoutBurningOldOwner() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_recoverer);
        assertEq(_kintoWalletv1.owners(0), _owner);

        // Start Recovery
        _kintoWalletv1.startRecovery();
        assertEq(_kintoWalletv1.inRecovery(), block.timestamp);
        vm.stopPrank();

        // Mint NFT to new owner
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(
            _kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](0);
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        vm.stopPrank();
        vm.startPrank(_owner);
        assertEq(_kintoIDv1.isKYC(_user), true);
        // Pass recovery time
        vm.warp(block.timestamp + _kintoWalletv1.RECOVERY_TIME() + 1);
        // Monitor AML
        address[] memory users = new address[](1);
        users[0] = _user;
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);
        vm.prank(_kycProvider);
        _kintoIDv1.monitor(users, updates);
        vm.prank(_recoverer);
        _kintoWalletv1.finishRecovery(users);
    }

    function testFailRecoverWithoutMintingNewOwner() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_recoverer);
        assertEq(_kintoWalletv1.owners(0), _owner);

        // Start Recovery
        _kintoWalletv1.startRecovery();
        assertEq(_kintoWalletv1.inRecovery(), block.timestamp);
        vm.stopPrank();

        // Burn old owner NFT
        vm.startPrank(_kycProvider);
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(
            _kintoIDv1, _owner, _owner, 1, block.timestamp + 1000);
        _kintoIDv1.burnKYC(sigdata);
        vm.stopPrank();
        vm.startPrank(_owner);
        assertEq(_kintoIDv1.isKYC(_user), true);
        // Pass recovery time
        vm.warp(block.timestamp + _kintoWalletv1.RECOVERY_TIME() + 1);
        address[] memory users = new address[](1);
        users[0] = _user;
        _kintoWalletv1.finishRecovery(users);
    }

    function testFailRecoverNotEnoughTime() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_recoverer);
        assertEq(_kintoWalletv1.owners(0), _owner);

        // Start Recovery
        _kintoWalletv1.startRecovery();
        assertEq(_kintoWalletv1.inRecovery(), block.timestamp);
        vm.stopPrank();

        // Mint NFT to new owner and burn old
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(
            _kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](0);
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        sigdata = _auxCreateSignature(_kintoIDv1, _owner, _owner, 1, block.timestamp + 1000);
        _kintoIDv1.burnKYC(sigdata);
        vm.stopPrank();
        vm.startPrank(_owner);
        assertEq(_kintoIDv1.isKYC(_user), true);
        // Pass recovery time (not enough)
        vm.warp(block.timestamp + _kintoWalletv1.RECOVERY_TIME() - 1);
        address[] memory users = new address[](1);
        users[0] = _user;
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);
        vm.prank(_kycProvider);
        _kintoIDv1.monitor(users, updates);
        vm.prank(_owner);
        _kintoWalletv1.finishRecovery(users);
    }

    /* ============ Helpers ============ */

    function _setPaymasterForContract(address _contract) private {
        vm.startPrank(_owner);
        vm.deal(_owner, 1e20);
        // We add the deposit to the counter contract in the paymaster
        _paymaster.addDepositFor{value: 5e18}(address(_contract));
        vm.stopPrank();
    }

}

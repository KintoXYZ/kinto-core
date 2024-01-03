// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/wallet/KintoWallet.sol";
import "../src/wallet/KintoWalletFactory.sol";
import "../src/tokens/EngenCredits.sol";
import "../src/paymasters/SponsorPaymaster.sol";
import "../src/KintoID.sol";
import {UserOp} from "./helpers/UserOp.sol";
import {UUPSProxy} from "./helpers/UUPSProxy.sol";
import {KYCSignature} from "./helpers/KYCSignature.sol";
import {AATestScaffolding} from "./helpers/AATestScaffolding.sol";

import "@aa/interfaces/IAccount.sol";
import "@aa/interfaces/INonceManager.sol";
import "@aa/interfaces/IEntryPoint.sol";
import "@aa/core/EntryPoint.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

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

contract KintoWalletTest is AATestScaffolding, UserOp {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoWalletv2 _kintoWalletv2;

    uint256 _chainID = 1;

    address payable _owner = payable(vm.addr(1));
    address _secondowner = address(2);
    address _user = vm.addr(3);
    address _user2 = vm.addr(5);
    address _upgrader = address(5);
    address _kycProvider = address(6);
    address _recoverer = address(7);

    function setUp() public {
        vm.chainId(_chainID);
        vm.startPrank(address(1));
        _owner.transfer(1e18);
        vm.stopPrank();
        deployAAScaffolding(_owner, _kycProvider, _recoverer);
        _setPaymasterForContract(address(_kintoWalletv1));
    }

    function testUp() public {
        assertEq(_kintoWalletv1.owners(0), _owner);
        assertEq(_entryPoint.walletFactory(), address(_walletFactory));
    }

    /* ============ Upgrade Tests ============ */

    function testFailOwnerCannotUpgrade() public {
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_owner);
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        KintoWalletv2 _implementationV2 = new KintoWalletv2(_entryPoint, _kintoIDv1);
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("upgradeTo(address)", address(_implementationV2)),
            address(_paymaster)
        );
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
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 3;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_user),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("upgradeTo(address)", address(_implementationV2)),
            address(_paymaster)
        );
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
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperation(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(counter),
            0,
            abi.encodeWithSignature("increment()")
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }

    function testFailTransactionViaPaymasterNoapproval() public {
        vm.startPrank(_owner);
        // Let's deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        vm.stopPrank();
        _setPaymasterForContract(address(counter));
        vm.startPrank(_owner);
        // Let's send a transaction to the counter contract through our wallet
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(counter),
            0,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        vm.expectRevert();
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
        uint256 startingNonce = _kintoWalletv1.getNonce();
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp2 = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce + 1,
            privateKeys,
            address(counter),
            0,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = createApprovalUserOp(
            _chainID,
            privateKeys,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce(),
            address(counter),
            address(_paymaster)
        );
        userOps[1] = userOp2;
        // Execute the transactions via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }

    function testMultipleTransactionsViaPaymaster() public {
        vm.startPrank(_owner);
        // Let's deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        vm.stopPrank();
        vm.startPrank(_owner);
        _setPaymasterForContract(address(counter));
        // Let's send a transaction to the counter contract through our wallet
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce + 1,
            privateKeys,
            address(counter),
            0,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );
        UserOperation memory userOp2 = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce + 2,
            privateKeys,
            address(counter),
            0,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](3);
        userOps[0] = createApprovalUserOp(
            _chainID, privateKeys, address(_kintoWalletv1), startingNonce, address(counter), address(_paymaster)
        );
        userOps[1] = userOp;
        userOps[2] = userOp2;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 2);
        vm.stopPrank();
    }

    function testMultipleTransactionsExecuteBatchPaymaster() public {
        vm.startPrank(_owner);
        // Let's deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        vm.stopPrank();
        vm.startPrank(_owner);
        _setPaymasterForContract(address(counter));
        address[] memory targets = new address[](3);
        targets[0] = address(_kintoWalletv1);
        targets[1] = address(counter);
        targets[2] = address(counter);
        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        bytes[] memory calls = new bytes[](3);
        address[] memory apps = new address[](1);
        apps[0] = address(counter);
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        calls[0] = abi.encodeWithSignature("setAppWhitelist(address[],bool[])", apps, flags);
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");

        OperationParams memory opParams = OperationParams({targetContracts: targets, values: values, bytesOps: calls});
        UserOperation memory userOp = this.createUserOperationBatchWithPaymaster(
            _chainID, address(_kintoWalletv1), startingNonce, privateKeys, opParams, address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 2);
        vm.stopPrank();
    }

    function testFailMultipleTransactionsExecuteBatchPaymasterRefuses() public {
        vm.startPrank(_owner);
        // Let's deploy the counter contract
        Counter counter = new Counter();
        Counter counter2 = new Counter();
        assertEq(counter.count(), 0);
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        vm.stopPrank();
        vm.startPrank(_owner);
        _setPaymasterForContract(address(counter));
        address[] memory targets = new address[](3);
        targets[0] = address(_kintoWalletv1);
        targets[1] = address(counter);
        targets[2] = address(counter2);
        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        bytes[] memory calls = new bytes[](3);
        address[] memory apps = new address[](1);
        apps[0] = address(counter);
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        calls[0] = abi.encodeWithSignature("setAppWhitelist(address[],bool[])", apps, flags);
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");
        // Let's send both transactions via batch
        OperationParams memory opParams = OperationParams({targetContracts: targets, values: values, bytesOps: calls});
        UserOperation memory userOp = this.createUserOperationBatchWithPaymaster(
            _chainID, address(_kintoWalletv1), startingNonce, privateKeys, opParams, address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        assertEq(counter2.count(), 1);
        vm.stopPrank();
    }

    /* ============ Signers & Policy Tests ============ */

    function testAddingOneSigner() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWalletv1.signerPolicy()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user);
        vm.stopPrank();
    }

    function testFailWithDuplicateSigner() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _owner;
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWalletv1.signerPolicy()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _owner);
        vm.stopPrank();
    }

    function testFailWithEmptyArray() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        address[] memory owners = new address[](0);
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWalletv1.signerPolicy()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(0), address(0));
        vm.stopPrank();
    }

    function testFailWithManyOwners() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        address[] memory owners = new address[](4);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user;
        owners[3] = _user;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWalletv1.signerPolicy()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(3), _user);
        vm.stopPrank();
    }

    function testFailWithoutKYCSigner() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        address[] memory owners = new address[](1);
        owners[0] = _user;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWalletv1.signerPolicy()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user);
        vm.stopPrank();
    }

    function testChangingPolicyWithTwoSigners() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWalletv1.ALL_SIGNERS()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user);
        assertEq(_kintoWalletv1.signerPolicy(), _kintoWalletv1.ALL_SIGNERS());
        vm.stopPrank();
    }

    function testChangingPolicyWithThreeSigners() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        address[] memory owners = new address[](3);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user2;
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWalletv1.MINUS_ONE_SIGNER()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user);
        assertEq(_kintoWalletv1.owners(2), _user2);
        assertEq(_kintoWalletv1.signerPolicy(), _kintoWalletv1.MINUS_ONE_SIGNER());
        vm.stopPrank();
    }

    function testFailChangingPolicyWithoutRightSigners() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("resetSigners(address[], uint8)", owners, _kintoWalletv1.signerPolicy()),
            address(_paymaster)
        );
        UserOperation memory userOp2 = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce + 1,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("setSignerPolicy(uint8)", _kintoWalletv1.ALL_SIGNERS()),
            address(_paymaster)
        );
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
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWalletv1.ALL_SIGNERS()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user);
        assertEq(_kintoWalletv1.signerPolicy(), _kintoWalletv1.ALL_SIGNERS());
        // Deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        vm.stopPrank();
        // Fund counter contract
        vm.startPrank(_owner);
        _setPaymasterForContract(address(counter));
        // Create counter increment transaction
        userOps = new UserOperation[](2);
        privateKeys = new uint256[](2);
        privateKeys[0] = 1;
        privateKeys[1] = 3;
        userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce() + 1,
            privateKeys,
            address(counter),
            0,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );
        userOps[0] = createApprovalUserOp(
            _chainID,
            privateKeys,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce(),
            address(counter),
            address(_paymaster)
        );
        userOps[1] = userOp;
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }

    function testFailMultisigTransaction() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWalletv1.ALL_SIGNERS()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user);
        assertEq(_kintoWalletv1.signerPolicy(), _kintoWalletv1.ALL_SIGNERS());
        // Deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        vm.stopPrank();
        // Fund counter contract
        vm.startPrank(_owner);
        _setPaymasterForContract(address(counter));
        // Create counter increment transaction
        userOps = new UserOperation[](2);
        privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce() + 1,
            privateKeys,
            address(counter),
            0,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );
        userOps[0] = createApprovalUserOp(
            _chainID,
            privateKeys,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce(),
            address(counter),
            address(_paymaster)
        );
        userOps[1] = userOp;

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }

    function testMultisigTransactionWith3Signers() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));

        // set 3 owners
        address[] memory owners = new address[](3);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user2;

        // get nonce
        uint256 startingNonce = _kintoWalletv1.getNonce();

        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;

        // generate the user operation wihch changes the policy to ALL_SIGNERS
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWalletv1.ALL_SIGNERS()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user);
        assertEq(_kintoWalletv1.signerPolicy(), _kintoWalletv1.ALL_SIGNERS());

        // Deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        vm.stopPrank();

        // Fund counter contract
        vm.startPrank(_owner);
        _setPaymasterForContract(address(counter));

        // Create counter increment transaction
        userOps = new UserOperation[](2);
        privateKeys = new uint256[](3);
        privateKeys[0] = 1;
        privateKeys[1] = 3;
        privateKeys[2] = 5;
        userOps[0] = createApprovalUserOp(
            _chainID,
            privateKeys,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce(),
            address(counter),
            address(_paymaster)
        );
        userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce() + 1,
            privateKeys,
            address(counter),
            0,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );
        userOps[1] = userOp;

        // execute
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }

    function testMultisigTransactionWith1SignerButSeveralOwners() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));

        // set 3 owners
        address[] memory owners = new address[](3);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user2;

        // get nonce
        uint256 startingNonce = _kintoWalletv1.getNonce();

        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;

        // generate the user operation wihch changes the policy to ALL_SIGNERS
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWalletv1.SINGLE_SIGNER()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user);
        assertEq(_kintoWalletv1.signerPolicy(), _kintoWalletv1.SINGLE_SIGNER());

        // Deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        vm.stopPrank();

        // Fund counter contract
        vm.startPrank(_owner);
        _setPaymasterForContract(address(counter));

        // Create counter increment transaction
        userOps = new UserOperation[](2);
        privateKeys = new uint256[](1);
        privateKeys[0] = 1;

        userOps[0] = createApprovalUserOp(
            _chainID,
            privateKeys,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce(),
            address(counter),
            address(_paymaster)
        );

        userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce() + 1,
            privateKeys,
            address(counter),
            0,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );
        userOps[1] = userOp;

        // execute
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }

    function testFailMultisigTransactionWhen2OutOf3Signers() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));

        // set 3 owners
        address[] memory owners = new address[](3);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user2;

        // get nonce
        uint256 startingNonce = _kintoWalletv1.getNonce();

        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;

        // generate the user operation wihch changes the policy to ALL_SIGNERS
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWalletv1.ALL_SIGNERS()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user);
        assertEq(_kintoWalletv1.signerPolicy(), _kintoWalletv1.ALL_SIGNERS());

        // Deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        vm.stopPrank();

        // Fund counter contract
        vm.startPrank(_owner);
        _setPaymasterForContract(address(counter));

        // Create counter increment transaction
        userOps = new UserOperation[](2);
        privateKeys = new uint256[](2);
        privateKeys[0] = 1;
        privateKeys[1] = 3;

        userOps[0] = createApprovalUserOp(
            _chainID,
            privateKeys,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce(),
            address(counter),
            address(_paymaster)
        );
        userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce() + 1,
            privateKeys,
            address(counter),
            0,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );
        userOps[0] = userOp;

        // execute
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }

    /* ============ Recovery Process ============ */

    function testRecoverAccountSuccessfully() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.stopPrank();
        vm.startPrank(_recoverer);
        assertEq(_kintoWalletv1.owners(0), _owner);

        // Start Recovery
        _walletFactory.startWalletRecovery(payable(address(_kintoWalletv1)));
        assertEq(_kintoWalletv1.inRecovery(), block.timestamp);
        vm.stopPrank();

        // Mint NFT to new owner and burn old
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
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
        _walletFactory.completeWalletRecovery(payable(address(_kintoWalletv1)), users);
        assertEq(_kintoWalletv1.inRecovery(), 0);
        assertEq(_kintoWalletv1.owners(0), _user);
    }

    function testFailRecoverNotRecoverer() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        assertEq(_kintoWalletv1.owners(0), _owner);

        // Start Recovery
        _walletFactory.startWalletRecovery(payable(address(_kintoWalletv1)));
    }

    function testFailDirectCall() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_recoverer);

        // Start Recovery
        _kintoWalletv1.startRecovery();
    }

    function testFailRecoverWithoutBurningOldOwner() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_recoverer);
        assertEq(_kintoWalletv1.owners(0), _owner);

        // Start Recovery
        _walletFactory.startWalletRecovery(payable(address(_kintoWalletv1)));
        assertEq(_kintoWalletv1.inRecovery(), block.timestamp);
        vm.stopPrank();

        // Mint NFT to new owner
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
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
        _walletFactory.completeWalletRecovery(payable(address(_kintoWalletv1)), users);
    }

    function testFailRecoverWithoutMintingNewOwner() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_recoverer);
        assertEq(_kintoWalletv1.owners(0), _owner);

        // Start Recovery
        _walletFactory.startWalletRecovery(payable(address(_kintoWalletv1)));
        assertEq(_kintoWalletv1.inRecovery(), block.timestamp);
        vm.stopPrank();

        // Burn old owner NFT
        vm.startPrank(_kycProvider);
        IKintoID.SignatureData memory sigdata =
            _auxCreateSignature(_kintoIDv1, _owner, _owner, 1, block.timestamp + 1000);
        _kintoIDv1.burnKYC(sigdata);
        vm.stopPrank();
        vm.startPrank(_owner);
        assertEq(_kintoIDv1.isKYC(_user), true);
        // Pass recovery time
        vm.warp(block.timestamp + _kintoWalletv1.RECOVERY_TIME() + 1);
        address[] memory users = new address[](1);
        users[0] = _user;
        _walletFactory.completeWalletRecovery(payable(address(_kintoWalletv1)), users);
    }

    function testFailRecoverNotEnoughTime() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        vm.startPrank(_recoverer);
        assertEq(_kintoWalletv1.owners(0), _owner);

        // Start Recovery
        _walletFactory.startWalletRecovery(payable(address(_kintoWalletv1)));
        assertEq(_kintoWalletv1.inRecovery(), block.timestamp);
        vm.stopPrank();

        // Mint NFT to new owner and burn old
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
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
        _walletFactory.completeWalletRecovery(payable(address(_kintoWalletv1)), users);
    }

    /* ============ Funder Whitelist ============ */

    function testWalletOwnersAreWhitelisted() public {
        vm.startPrank(_owner);
        assertEq(_kintoWalletv1.isFunderWhitelisted(_owner), true);
        assertEq(_kintoWalletv1.isFunderWhitelisted(_user), false);
        assertEq(_kintoWalletv1.isFunderWhitelisted(_user2), false);
        vm.stopPrank();
    }

    function testAddingOneFunder() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        address[] memory funders = new address[](1);
        funders[0] = address(23);
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("setFunderWhitelist(address[],bool[])", funders, flags),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.isFunderWhitelisted(address(23)), true);
        vm.stopPrank();
    }

    /* ============ Token Approvals ============ */

    function testApproveTokens() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        address app = address(100);
        address[] memory tokens = new address[](1);
        tokens[0] = address(_engenCredits);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e12;

        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;

        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce + 1,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("approveTokens(address,address[],uint256[])", app, tokens, amounts),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = createApprovalUserOp(
            _chainID, privateKeys, address(_kintoWalletv1), _kintoWalletv1.getNonce(), address(app), address(_paymaster)
        );
        userOps[1] = userOp;

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.isTokenApproved(app, tokens[0]), 1e12);
        assertEq(_kintoWalletv1.isTokenApproved(app, address(24)), 0);
        vm.stopPrank();
    }

    function testFailApproveTokensWithoutWhitelist() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        address app = address(100);
        address[] memory tokens = new address[](1);
        tokens[0] = address(_engenCredits);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e12;

        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;

        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce + 1,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("approveTokens(address,address[],uint256[])", app, tokens, amounts),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = userOp;

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.isTokenApproved(app, tokens[0]), 1e12);
        assertEq(_kintoWalletv1.isTokenApproved(app, address(24)), 0);
        vm.stopPrank();
    }

    function testApproveAndRevokeTokens() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        address app = address(100);
        address[] memory tokens = new address[](1);
        tokens[0] = address(_engenCredits);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e12;

        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;

        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce + 1,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("approveTokens(address,address[],uint256[])", app, tokens, amounts),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = createApprovalUserOp(
            _chainID, privateKeys, address(_kintoWalletv1), _kintoWalletv1.getNonce(), address(app), address(_paymaster)
        );
        userOps[1] = userOp;

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.isTokenApproved(app, tokens[0]), 1e12);
        assertEq(_kintoWalletv1.isTokenApproved(app, address(24)), 0);

        userOps = new UserOperation[](1);
        userOps[0] = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce(),
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("revokeTokens(address,address[])", app, tokens),
            address(_paymaster)
        );
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.isTokenApproved(app, tokens[0]), 0);

        vm.stopPrank();
    }

    function testFailCallingApproveDirectly() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_engenCredits));
        address app = address(100);

        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;

        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce + 1,
            privateKeys,
            address(_engenCredits),
            0,
            abi.encodeWithSignature("approve(address,uint256)", address(app), 1e12),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = createApprovalUserOp(
            _chainID,
            privateKeys,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce(),
            address(_engenCredits),
            address(_paymaster)
        );
        userOps[1] = userOp;

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_engenCredits.allowance(address(_kintoWalletv1), app), 1e12);
        vm.stopPrank();
    }

    /* ============ App Key ============ */

    function testFailSettingAppKeyNoWhitelist() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        address app = address(_engenCredits);
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("setAppKey(address,address)", app, _user),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.appSigner(app), _user);
        vm.stopPrank();
    }

    function testSettingAppKey() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));
        address app = address(_engenCredits);
        uint256 startingNonce = _kintoWalletv1.getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce + 1,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("setAppKey(address,address)", app, _user),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = createApprovalUserOp(
            _chainID,
            privateKeys,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce(),
            address(_engenCredits),
            address(_paymaster)
        );
        userOps[1] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.appSigner(app), _user);
        vm.stopPrank();
    }

    function testMultisigTransactionWith2SignersWithAppkey() public {
        vm.startPrank(_owner);
        _setPaymasterForContract(address(_kintoWalletv1));

        // set 2 owners
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user2;

        // get nonce
        uint256 startingNonce = _kintoWalletv1.getNonce();

        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;

        // generate the user operation wihch changes the policy to ALL_SIGNERS
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWalletv1.ALL_SIGNERS()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWalletv1.owners(1), _user2);
        assertEq(_kintoWalletv1.signerPolicy(), _kintoWalletv1.ALL_SIGNERS());

        // Deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        vm.stopPrank();

        // Fund counter contract
        vm.startPrank(_owner);
        _setPaymasterForContract(address(counter));

        // Create counter increment transaction
        userOps = new UserOperation[](2);
        privateKeys = new uint256[](2);
        privateKeys[0] = 1;
        privateKeys[1] = 5;
        userOps[0] = createApprovalUserOp(
            _chainID,
            privateKeys,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce(),
            address(counter),
            address(_paymaster)
        );
        userOps[1] = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce() + 1,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("setAppKey(address,address)", address(counter), _user),
            address(_paymaster)
        );
        _entryPoint.handleOps(userOps, payable(_owner));
        userOps = new UserOperation[](1);
        console.log("counter address", address(counter));
        console.log("user address", _user);
        // Set only app key signature
        uint256[] memory privateKeysApp = new uint256[](1);
        privateKeysApp[0] = 3;
        userOps[0] = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            _kintoWalletv1.getNonce(),
            privateKeysApp,
            address(counter),
            0,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // execute
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }
}

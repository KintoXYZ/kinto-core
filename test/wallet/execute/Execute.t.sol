// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@aa/interfaces/IEntryPoint.sol";

import "../../../src/interfaces/IKintoWallet.sol";

import "../../../src/wallet/KintoWallet.sol";
import "../../../src/sample/Counter.sol";

import {UserOp} from "../../helpers/UserOp.sol";
import {AATestScaffolding} from "../../helpers/AATestScaffolding.sol";

contract ExecuteBatchTest is AATestScaffolding, UserOp {
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
        _fundPaymasterForContract(address(_kintoWallet));

        // Default tests to use 1 private key for simplicity
        privateKeys = new uint256[](1);

        // Default tests to use _ownerPk unless otherwise specified
        privateKeys[0] = _ownerPk;
    }

    function testUp() public {
        assertEq(_kintoWallet.owners(0), _owner);
        assertEq(_entryPoint.walletFactory(), address(_walletFactory));
    }

    /* ============ One Signer Account Transaction Tests (execute) ============ */

    function test_RevertWhen_SendingTransactionDirectlyAndPrefundNotPaid() public {
        // deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        registerApp(_owner, "test", address(counter));

        // send a transaction to the counter contract through our wallet
        // without a paymaster and without prefunding the wallet
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()")
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // execute the transaction via the entry point
        vm.expectRevert(abi.encodeWithSignature("FailedOp(uint256,string)", 0, "AA21 didn't pay prefund"));
        _entryPoint.handleOps(userOps, payable(_owner));
    }

    function test_RevertWhen_SendingTransactionDirectlyAndPrefund() public {
        // deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        registerApp(_owner, "test", address(counter));
        // prefund wallet
        vm.deal(address(_kintoWallet), 1 ether);

        UserOperation[] memory userOps = new UserOperation[](2);

        // whitelist app
        userOps[0] = _whitelistAppOp(
            privateKeys, address(_kintoWallet), _kintoWallet.getNonce(), address(counter), address(_paymaster)
        );

        // send a transaction to the counter contract through our wallet
        // without a paymaster but prefunding the wallet
        userOps[1] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce() + 1,
            privateKeys,
            abi.encodeWithSignature("increment()")
        );

        // execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
    }

    function testTransaction_RevertWhen_AppNotRegisteredAndNotWhitelisted() public {
        // (1). deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);

        // (2). fund paymaster for Counter contract
        _fundPaymasterForContract(address(counter));

        // (3). Create Counter increment user op
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // (4). execute the transaction via the entry point
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq("KW: contract not whitelisted");
        assertEq(counter.count(), 0);
    }

    function testTransaction_RevertWhen_AppRegisteredButNotWhitelisted() public {
        // (1). deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);

        // (2). fund paymaster for Counter contract
        _fundPaymasterForContract(address(counter));

        // (3). register app
        registerApp(_owner, "test", address(counter));

        // (4). Create Counter increment user op
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // (5). execute the transaction via the entry point
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq("KW: contract not whitelisted");
        assertEq(counter.count(), 0);
    }

    function testTransactionViaPaymaster() public {
        vm.startPrank(_owner);
        // Let's deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        vm.stopPrank();
        _fundPaymasterForContract(address(counter));
        registerApp(_owner, "test", address(counter));
        vm.startPrank(_owner);
        // Let's send a transaction to the counter contract through our wallet
        uint256 nonce = _kintoWallet.getNonce();
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        UserOperation memory userOp2 = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            nonce + 1,
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = _whitelistAppOp(
            privateKeys, address(_kintoWallet), _kintoWallet.getNonce(), address(counter), address(_paymaster)
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
        uint256 nonce = _kintoWallet.getNonce();
        vm.stopPrank();
        registerApp(_owner, "test", address(counter));
        vm.startPrank(_owner);
        _fundPaymasterForContract(address(counter));
        // Let's send a transaction to the counter contract through our wallet
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            nonce + 1,
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );
        UserOperation memory userOp2 = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            nonce + 2,
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](3);
        userOps[0] = _whitelistAppOp(privateKeys, address(_kintoWallet), nonce, address(counter), address(_paymaster));
        userOps[1] = userOp;
        userOps[2] = userOp2;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 2);
        vm.stopPrank();
    }

    /* ============ Multisig Transactions ============ */

    function testMultisigTransaction() public {
        // (1). generate resetSigners UserOp to set 2 owners
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;

        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWallet.ALL_SIGNERS()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // (2). execute the transaction via the entry point
        vm.expectEmit();
        emit WalletPolicyChanged(_kintoWallet.ALL_SIGNERS(), _kintoWallet.SINGLE_SIGNER());
        _entryPoint.handleOps(userOps, payable(_owner));

        assertEq(_kintoWallet.owners(1), _user);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.ALL_SIGNERS());

        // (3). deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);

        // (4). fund paymaster for Counter contract
        _fundPaymasterForContract(address(counter));
        registerApp(_owner, "test", address(counter));

        // (5). Set private keys
        privateKeys = new uint256[](2);
        privateKeys[0] = _ownerPk;
        privateKeys[1] = _userPk;

        // (6). Create 2 user ops:
        userOps = new UserOperation[](2);
        // a. whitelist app
        userOps[0] = _whitelistAppOp(
            privateKeys, address(_kintoWallet), _kintoWallet.getNonce(), address(counter), address(_paymaster)
        );

        // b. Counter increment
        userOps[1] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce() + 1,
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // (7). execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
    }

    function test_RevertWhen_MultisigTransaction() public {
        // (1). generate resetSigners UserOp to set 2 owners
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;

        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWallet.ALL_SIGNERS()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // (2). execute the transaction via the entry point
        vm.expectEmit();
        emit WalletPolicyChanged(_kintoWallet.ALL_SIGNERS(), _kintoWallet.SINGLE_SIGNER());
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWallet.owners(1), _user);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.ALL_SIGNERS());

        // (3). deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);

        // (4). fund paymaster for Counter contract
        _fundPaymasterForContract(address(counter));
        registerApp(_owner, "test", address(counter));

        // (5). Create 2 user ops:
        userOps = new UserOperation[](2);

        // a. whitelist app
        userOps[0] = _whitelistAppOp(
            privateKeys, address(_kintoWallet), _kintoWallet.getNonce(), address(counter), address(_paymaster)
        );

        // b. Counter increment
        userOps[1] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce() + 1,
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // (7). execute the transaction via the entry point
        vm.expectRevert(abi.encodeWithSignature("FailedOp(uint256,string)", 0, "AA24 signature error"));
        _entryPoint.handleOps(userOps, payable(_owner));
    }

    function testMultisigTransactionWith3Signers() public {
        // (1). generate resetSigners UserOp to set 3 owners
        address[] memory owners = new address[](3);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user2;

        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWallet.ALL_SIGNERS()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // (2). execute the transaction via the entry point
        vm.expectEmit();
        emit WalletPolicyChanged(_kintoWallet.ALL_SIGNERS(), _kintoWallet.SINGLE_SIGNER());
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWallet.owners(1), _user);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.ALL_SIGNERS());

        // (3). deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        vm.stopPrank();

        // (4). fund paymaster for Counter contract
        _fundPaymasterForContract(address(counter));
        registerApp(_owner, "test", address(counter));

        // (5). Set private keys
        privateKeys = new uint256[](3);
        privateKeys[0] = _ownerPk;
        privateKeys[1] = _userPk;
        privateKeys[2] = _user2Pk;

        // (6). Create 2 user ops:
        userOps = new UserOperation[](2);
        // a. whitelist app
        userOps[0] = _whitelistAppOp(
            privateKeys, address(_kintoWallet), _kintoWallet.getNonce(), address(counter), address(_paymaster)
        );
        // b. Counter increment
        userOps[1] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce() + 1,
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // (7). execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
    }

    function testMultisigTransactionWith1SignerButSeveralOwners() public {
        // (1). deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);

        // (2). fund paymaster for Counter contract
        _fundPaymasterForContract(address(counter));
        registerApp(_owner, "test", address(counter));

        // (3). Create 2 user ops:
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps = new UserOperation[](2);
        // a. whitelist app
        userOps[0] = _whitelistAppOp(
            privateKeys, address(_kintoWallet), _kintoWallet.getNonce(), address(counter), address(_paymaster)
        );

        // b. Counter increment
        userOps[1] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce() + 1,
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // (4). execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }

    function test_RevertWhen_MultisigTransactionHas2OutOf3Signers() public {
        // (1). generate resetSigners UserOp to set 3 owners
        address[] memory owners = new address[](3);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user2;

        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWallet.ALL_SIGNERS()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // (2). execute the transaction via the entry point
        vm.expectEmit();
        emit WalletPolicyChanged(_kintoWallet.ALL_SIGNERS(), _kintoWallet.SINGLE_SIGNER());
        _entryPoint.handleOps(userOps, payable(_owner));

        assertEq(_kintoWallet.owners(1), _user);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.ALL_SIGNERS());

        // (3). deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);

        // (4). fund paymaster for Counter contract
        _fundPaymasterForContract(address(counter));
        registerApp(_owner, "test", address(counter));

        // (5). Set private keys
        privateKeys = new uint256[](2);
        privateKeys[0] = _ownerPk;
        privateKeys[1] = _userPk;

        // (6). Create 2 user ops:
        userOps = new UserOperation[](2);

        // a. whitelist app
        userOps[0] = _whitelistAppOp(
            privateKeys, address(_kintoWallet), _kintoWallet.getNonce(), address(counter), address(_paymaster)
        );

        // b. Counter increment
        userOps[1] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce() + 1,
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // (7). execute the transaction via the entry point
        vm.expectRevert(abi.encodeWithSignature("FailedOp(uint256,string)", 0, "AA24 signature error"));
        _entryPoint.handleOps(userOps, payable(_owner));
    }
}

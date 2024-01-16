// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@aa/interfaces/IEntryPoint.sol";

import "../src/interfaces/IKintoWallet.sol";
import "../src/wallet/KintoWallet.sol";
import "../src/sample/Counter.sol";

import {UserOp} from "./helpers/UserOp.sol";
import {AATestScaffolding} from "./helpers/AATestScaffolding.sol";

contract KintoWalletTest is AATestScaffolding, UserOp {
    uint256[] privateKeys;

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

    /* ============ Upgrade Tests ============ */

    // FIXME: I think these upgrade tests are wrong because, basically, the KintoWallet.sol does not have
    // an upgrade function. The upgrade function is in the UUPSUpgradeable.sol contract.
    function test_RevertWhen_OwnerCannotUpgrade() public {
        // deploy a new implementation
        KintoWallet _newImplementation = new KintoWallet(_entryPoint, _kintoIDv1, _kintoAppRegistry);

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

    function test_RevertWhen_OthersCannotUpgrade() public {
        // create a wallet for _user
        approveKYC(_kycProvider, _user, _userPk);
        vm.broadcast(_user);
        IKintoWallet userWallet = _walletFactory.createAccount(_user, _recoverer, 0);

        // deploy a new implementation
        KintoWallet _newImplementation = new KintoWallet(_entryPoint, _kintoIDv1, _kintoAppRegistry);

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

        // execute the transaction via the entry point
        // @dev handleOps seems to fail silently (does not revert)
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(_entryPoint.getUserOpHash(userOp), userOp.sender, userOp.nonce, bytes(""));

        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq("KW: contract not whitelisted");

        vm.stopPrank();
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

    /* ============ One Signer Account Transaction Tests (executeBatch) ============ */

    function testMultipleTransactionsExecuteBatchPaymaster() public {
        vm.startPrank(_owner);
        // Let's deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        uint256 nonce = _kintoWallet.getNonce();
        vm.stopPrank();
        registerApp(_owner, "test", address(counter));
        vm.startPrank(_owner);
        _fundPaymasterForContract(address(counter));
        address[] memory targets = new address[](3);
        targets[0] = address(_kintoWallet);
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
        calls[0] = abi.encodeWithSignature("whitelistApp(address[],bool[])", apps, flags);
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation memory userOp =
            _createUserOperation(address(_kintoWallet), nonce, privateKeys, opParams, address(_paymaster));
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 2);
        vm.stopPrank();
    }

    function test_RevertWhen_MultipleTransactionsExecuteBatchPaymasterRefuses() public {
        // deploy the counter contract
        Counter counter = new Counter();
        Counter counter2 = new Counter();
        assertEq(counter.count(), 0);
        assertEq(counter2.count(), 0);

        // only fund counter
        _fundPaymasterForContract(address(counter));

        registerApp(_owner, "test", address(counter));

        // prep batch
        address[] memory targets = new address[](3);
        targets[0] = address(_kintoWallet);
        targets[1] = address(counter);
        targets[2] = address(counter2);

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        address[] memory apps = new address[](1);
        apps[0] = address(counter);

        bool[] memory flags = new bool[](1);
        flags[0] = true;

        // we want to do 3 calls: whitelistApp, increment counter and increment counter2
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSignature("whitelistApp(address[],bool[])", apps, flags);
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");

        // send all transactions via batch
        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // execute the transaction via the entry point

        // prepare expected error message
        uint256 expectedOpIndex = 0; // Adjust as needed
        string memory expectedMessage = "AA33 reverted";
        bytes memory additionalMessage =
            abi.encodePacked("SP: executeBatch targets must be sponsored by the contract or be the sender wallet");
        bytes memory expectedAdditionalData = abi.encodeWithSelector(
            bytes4(keccak256("Error(string)")), // Standard error selector
            additionalMessage
        );

        // encode the entire revert reason
        bytes memory expectedRevertReason = abi.encodeWithSignature(
            "FailedOpWithRevert(uint256,string,bytes)", expectedOpIndex, expectedMessage, expectedAdditionalData
        );

        vm.expectRevert(expectedRevertReason);
        _entryPoint.handleOps(userOps, payable(_owner));
    }

    /* ============ Signers & Policy Tests ============ */

    function testAddingOneSigner() public {
        vm.startPrank(_owner);
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        uint256 nonce = _kintoWallet.getNonce();
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            nonce,
            privateKeys,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWallet.signerPolicy()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWallet.owners(1), _user);
        vm.stopPrank();
    }

    function test_RevertWhen_DuplicateSigner() public {
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _owner;

        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWallet.signerPolicy()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // execute the transaction via the entry point
        // @dev handleOps fails silently (does not revert)
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq("duplicate owners");
    }

    function test_RevertWhen_WithEmptyArray() public {
        address[] memory owners = new address[](0);

        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWallet.signerPolicy()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // execute the transaction via the entry point
        // @dev handleOps fails silently (does not revert)
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        // fixme: assertRevertReasonEq(stdError.indexOOBError)F;
    }

    function test_RevertWhen_WithManyOwners() public {
        address[] memory owners = new address[](4);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user;
        owners[3] = _user;

        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWallet.signerPolicy()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // execute the transaction via the entry point
        // @dev handleOps fails silently (does not revert)
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq("KW-rs: invalid array");
    }

    function test_RevertWhen_WithoutKYCSigner() public {
        address[] memory owners = new address[](1);
        owners[0] = _user;

        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWallet.signerPolicy()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
    }

    function testChangingPolicyWithTwoSigners() public {
        vm.startPrank(_owner);
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        uint256 nonce = _kintoWallet.getNonce();
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            nonce,
            privateKeys,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWallet.ALL_SIGNERS()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWallet.owners(1), _user);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.ALL_SIGNERS());
        vm.stopPrank();
    }

    function testChangingPolicyWithThreeSigners() public {
        vm.startPrank(_owner);
        address[] memory owners = new address[](3);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user2;
        uint256 nonce = _kintoWallet.getNonce();
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            nonce,
            privateKeys,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWallet.MINUS_ONE_SIGNER()),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWallet.owners(1), _user);
        assertEq(_kintoWallet.owners(2), _user2);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.MINUS_ONE_SIGNER());
        vm.stopPrank();
    }

    function test_RevertWhen_ChangingPolicyWithoutRightSigners() public {
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;

        uint256 nonce = _kintoWallet.getNonce();

        // call setSignerPolicy with ALL_SIGNERS policy should revert because the wallet has 1 owners
        // and the policy requires 3 owners.
        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            nonce,
            privateKeys,
            abi.encodeWithSignature("setSignerPolicy(uint8)", _kintoWallet.ALL_SIGNERS()),
            address(_paymaster)
        );

        // call resetSigners with existing policy (SINGLE_SIGNER) should revert because I'm passing 2 owners
        userOps[1] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            nonce + 1,
            privateKeys,
            abi.encodeWithSignature("resetSigners(address[], uint8)", owners, _kintoWallet.signerPolicy()),
            address(_paymaster)
        );

        // expect revert events for the 2 ops
        // @dev handleOps fails silently (does not revert)
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );

        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[1]), userOps[1].sender, userOps[1].nonce, bytes("")
        );

        // Execute the transaction via the entry point
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));

        bytes[] memory reasons = new bytes[](2);
        reasons[0] = "invalid policy";
        reasons[1] = "Address: low-level call with value failed";
        assertRevertReasonEq(reasons);

        assertEq(_kintoWallet.owners(0), _owner);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.SINGLE_SIGNER());
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

    /* ============ Funder Whitelist ============ */

    function testWalletOwnersAreWhitelisted() public {
        vm.startPrank(_owner);
        assertEq(_kintoWallet.isFunderWhitelisted(_owner), true);
        assertEq(_kintoWallet.isFunderWhitelisted(_user), false);
        assertEq(_kintoWallet.isFunderWhitelisted(_user2), false);
        vm.stopPrank();
    }

    function testAddingOneFunder() public {
        vm.startPrank(_owner);
        address[] memory funders = new address[](1);
        funders[0] = address(23);
        uint256 nonce = _kintoWallet.getNonce();
        bool[] memory flags = new bool[](1);
        flags[0] = true;
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
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWallet.isFunderWhitelisted(address(23)), true);
        vm.stopPrank();
    }

    /* ============ App Key ============ */

    function test_RevertWhen_SettingAppKeyNoWhitelist() public {
        address app = address(_engenCredits);
        registerApp(_owner, "test", address(_engenCredits));
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("setAppKey(address,address)", app, _user),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        // Execute the transaction via the entry point
        address appSignerBefore = _kintoWallet.appSigner(app);
        // @dev handleOps fails silently (does not revert)
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq("KW-apk: invalid address");
        assertEq(_kintoWallet.appSigner(app), appSignerBefore);
    }

    function testSettingAppKey() public {
        address app = address(_engenCredits);
        uint256 nonce = _kintoWallet.getNonce();
        registerApp(_owner, "test", address(_engenCredits));

        UserOperation[] memory userOps = new UserOperation[](2);
        userOps[0] =
            _whitelistAppOp(privateKeys, address(_kintoWallet), nonce, address(_engenCredits), address(_paymaster));

        userOps[1] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            nonce + 1,
            privateKeys,
            abi.encodeWithSignature("setAppKey(address,address)", app, _user),
            address(_paymaster)
        );

        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWallet.appSigner(app), _user);
    }

    function testMultisigTransactionWith2SignersWithAppkey() public {
        vm.startPrank(_owner);
        // set 2 owners
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user2;

        // generate the user operation wihch changes the policy to ALL_SIGNERS
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

        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWallet.owners(1), _user2);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.ALL_SIGNERS());

        // Deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        vm.stopPrank();
        registerApp(_owner, "test", address(counter));

        // Fund counter contract
        vm.startPrank(_owner);
        _fundPaymasterForContract(address(counter));

        // Create counter increment transaction
        userOps = new UserOperation[](2);
        privateKeys = new uint256[](2);
        privateKeys[0] = _ownerPk;
        privateKeys[1] = _user2Pk;
        userOps[0] = _whitelistAppOp(
            privateKeys, address(_kintoWallet), _kintoWallet.getNonce(), address(counter), address(_paymaster)
        );
        userOps[1] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce() + 1,
            privateKeys,
            abi.encodeWithSignature("setAppKey(address,address)", address(counter), _user),
            address(_paymaster)
        );
        _entryPoint.handleOps(userOps, payable(_owner));
        userOps = new UserOperation[](1);

        // Set only app key signature
        uint256[] memory privateKeysApp = new uint256[](1);
        privateKeysApp[0] = 3;
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeysApp,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // execute
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        vm.stopPrank();
    }

    /* ============ Whitelist ============ */

    function testWhitelistRegisteredApp() public {
        // (1). deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);

        // (2). fund paymaster for Counter contract
        _fundPaymasterForContract(address(counter));

        // (3). register app
        registerApp(_owner, "test", address(counter));

        // (4). Create whitelist app user op
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _whitelistAppOp(
            privateKeys, address(_kintoWallet), _kintoWallet.getNonce(), address(counter), address(_paymaster)
        );

        // (5). execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
    }

    // function testWhitelist_revertWhen_AppNotRegistered() public {
    //     // (1). deploy Counter contract
    //     Counter counter = new Counter();
    //     assertEq(counter.count(), 0);

    //     // (2). fund paymaster for Counter contract
    //     _fundPaymasterForContract(address(counter));

    //     // (3). Create whitelist app user op
    //     UserOperation[] memory userOps = new UserOperation[](1);
    //     userOps[0] = _whitelistAppOp(
    //         privateKeys, address(_kintoWallet), _kintoWallet.getNonce(), address(counter), address(_paymaster)
    //     );

    //     // (4). execute the transaction via the entry point and expect a revert event
    //     vm.expectEmit(true, true, true, false);
    //     emit UserOperationRevertReason(
    //         _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
    //     );
    //     vm.recordLogs();
    //     _entryPoint.handleOps(userOps, payable(_owner));
    //     assertRevertReasonEq("KW-apw: app must be registered");
    // }
}

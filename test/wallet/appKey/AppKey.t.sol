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

contract AppKeyTest is AATestScaffolding, UserOp {
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

    /* ============ App Key ============ */

    function testSetAppKey() public {
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

    // execute
    function testSetAppKey_RevertWhen_AppIsNotWhitelisted() public {
        registerApp(_owner, "test", address(_engenCredits));

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("setAppKey(address,address)", address(_engenCredits), _user),
            address(_paymaster)
        );

        // execute the transaction via the entry point
        address appSignerBefore = _kintoWallet.appSigner(address(_engenCredits));

        // @dev handleOps fails silently (does not revert)
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq("KW-apk: contract not whitelisted");
        assertEq(_kintoWallet.appSigner(address(_engenCredits)), appSignerBefore);
    }

    function testExecute_When2Signers_WhenUsingAppkey() public {
        // set 2 owners
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user2;

        // generate the user operation which changes the policy to ALL_SIGNERS
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

        // execute the transaction via the entry point
        vm.prank(_owner);
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWallet.owners(1), _user2);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.ALL_SIGNERS());

        // deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);

        // register app
        registerApp(_owner, "test", address(counter));

        // fund counter contract
        _fundSponsorForApp(address(counter));

        // prep user ops (whitelist and set app key)
        privateKeys = new uint256[](2);
        privateKeys[0] = _ownerPk;
        privateKeys[1] = _user2Pk;

        userOps = new UserOperation[](2);
        userOps[0] = _whitelistAppOp(
            privateKeys, address(_kintoWallet), _kintoWallet.getNonce(), address(counter), address(_paymaster)
        );

        // set app key signature
        userOps[1] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce() + 1,
            privateKeys,
            abi.encodeWithSignature("setAppKey(address,address)", address(counter), _user),
            address(_paymaster)
        );
        vm.prank(_owner);
        _entryPoint.handleOps(userOps, payable(_owner));

        // create counter increment transaction
        userOps = new UserOperation[](1);
        uint256[] memory privateKeysApp = new uint256[](1);
        privateKeysApp[0] = _userPk;

        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeysApp,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // execute
        vm.prank(_owner);
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
    }

    function testExecute_WhenUsingAppkey_WhenSignerIsOwner() public {
        // deploy Counter contract
        Counter counter = new Counter();
        registerApp(_owner, "test", address(counter));
        whitelistApp(address(counter));

        // fund counter contract
        _fundSponsorForApp(address(counter));

        // set app key signature
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("setAppKey(address,address)", address(counter), _user),
            address(_paymaster)
        );

        _entryPoint.handleOps(userOps, payable(_owner));

        // create Counter increment transaction
        userOps = new UserOperation[](1);
        privateKeys = new uint256[](1);
        privateKeys[0] = _userPk; // we want to make use of the app key

        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // execute
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
    }

    function testExecute_WhenUsingAppkey_WhenSignerIsOwner_WhenAppNotWhitelisted() public {
        // deploy Counter contract
        Counter counter = new Counter();
        registerApp(_owner, "test", address(counter));
        // whitelistApp(address(counter));

        // fund counter contract
        _fundSponsorForApp(address(counter));

        // set app key signature
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("setAppKey(address,address)", address(counter), _user),
            address(_paymaster)
        );

        _entryPoint.handleOps(userOps, payable(_owner));

        // create Counter increment transaction
        userOps = new UserOperation[](1);
        privateKeys = new uint256[](1);
        privateKeys[0] = _userPk; // we want to make use of the app key

        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        // execute the transaction via the entry point
        // @dev handleOps seems to fail silently (does not revert)
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );

        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq("KW: contract not whitelisted");
    }

    function testExecute_WhenUsingAppkey_WhenCallToWallet_WhenSignerIsOwner() public {
        // should skip the verification through app key and just use the policy of the wallet

        // deploy Counter contract
        Counter counter = new Counter();
        registerApp(_owner, "test", address(counter));
        whitelistApp(address(counter));

        // fund counter contract
        _fundSponsorForApp(address(counter));

        // set app key signature
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("setAppKey(address,address)", address(counter), _user),
            address(_paymaster)
        );

        _entryPoint.handleOps(userOps, payable(_owner));

        // try doing a wallet call and it should work
        address[] memory apps = new address[](1);
        apps[0] = address(counter);
        bool[] memory flags = new bool[](1);
        flags[0] = false;

        userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("whitelistApp(address[],bool[])", apps, flags),
            address(_paymaster)
        );

        // execute
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWallet.appWhitelist(address(counter)), false);
    }

    function testExecute_Revert_WhenUsingAppkey_WhenSignerIsAppKey_WhenCallToWallet() public {
        // deploy Counter contract
        Counter counter = new Counter();
        registerApp(_owner, "test", address(counter));
        whitelistApp(address(counter));

        // fund counter contract
        _fundSponsorForApp(address(counter));

        // set app key signature
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("setAppKey(address,address)", address(counter), _user),
            address(_paymaster)
        );
        _entryPoint.handleOps(userOps, payable(_owner));

        // create Counter increment transaction
        userOps = new UserOperation[](1);
        privateKeys = new uint256[](1);
        privateKeys[0] = _userPk; // we want to make use of the app key

        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("isFunderWhitelisted()"),
            address(_paymaster)
        );

        // execute
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
    }

    // execute batch
    function testExecuteBatch_WhenUsingAppkey_WhenSignerIsOwner_WhenNonWalletOps() public {} // should skip the verification through app key and just use the policy of the wallet

    function testExecuteBatch_WhenUsingAppkey_WhenSignerIsOwner_WhenAllWalletOps() public {} // should skip the verification through app key and just use the policy of the wallet

    function testExecuteBatch_WhenUsingAppkey_WhenSignerIsAppKey_WhenNonWalletOps() public {} // should use the app key

    function testExecuteBatch_Revert_WhenUsingAppkey_WhenSignerIsAppKey_WhenFirstOpIsWallet() public {
        // should skip app key verification because one of the targets is wallet and this is not allowed
        // and then revert with AA24 signature error because signer is not the owner

        // deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);

        console.log("COUNTERRR", address(counter));
        console.log("WALLETTT", address(_kintoWallet));

        // fund paymaster for Counter contract
        _fundSponsorForApp(address(counter));

        registerApp(_owner, "test", address(counter));
        whitelistApp(address(counter));

        // set app key signature
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("setAppKey(address,address)", address(counter), _user),
            address(_paymaster)
        );
        _entryPoint.handleOps(userOps, payable(_owner));

        // prep batch
        address[] memory targets = new address[](3);
        targets[0] = address(_kintoWallet);
        targets[1] = address(counter);
        targets[2] = address(counter);

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        bytes[] memory calls = new bytes[](3);

        // whitelist app params
        address[] memory apps = new address[](1);
        apps[0] = address(counter);
        bool[] memory flags = new bool[](1);
        flags[0] = true;

        // 3 calls batch: whitelistApp and increment counter (two times)
        calls[0] = abi.encodeWithSignature("whitelistApp(address[],bool[])", apps, flags);
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        userOps = new UserOperation[](1);
        privateKeys = new uint256[](1);
        privateKeys[0] = _userPk; // we want to make use of the app key

        userOps[0] = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        vm.expectRevert(abi.encodeWithSignature("FailedOp(uint256,string)", 0, "AA24 signature error"));
        _entryPoint.handleOps(userOps, payable(_owner));
    }

    function testExecuteBatch_Revert_WhenUsingAppkey_WhenSignerIsAppKey_WhenLastOpIsWallet() public {
        // should skip app key verification because one of the targets is wallet and this is not allowed
        // and then revert with AA24 signature error because signer is not the owner

        // FIXME: what is actually happening is that it is failing on the paymaster because, when it gets the sponsor,
        // either this the above should be fixed so they are consistent.

        // deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        console.log("COUNTERRR", address(counter));
        console.log("WALLETTT", address(_kintoWallet));

        // fund paymaster for Counter contract
        _fundSponsorForApp(address(counter));

        registerApp(_owner, "test", address(counter));
        whitelistApp(address(counter));

        // set app key signature
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("setAppKey(address,address)", address(counter), _user),
            address(_paymaster)
        );
        _entryPoint.handleOps(userOps, payable(_owner));

        // prep batch
        address[] memory targets = new address[](3);
        targets[0] = address(counter);
        targets[1] = address(counter);
        targets[2] = address(_kintoWallet);

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        bytes[] memory calls = new bytes[](3);

        // whitelist app params
        address[] memory apps = new address[](1);
        apps[0] = address(counter);
        bool[] memory flags = new bool[](1);
        flags[0] = true;

        // 3 calls batch: whitelistApp and increment counter (two times)
        calls[0] = abi.encodeWithSignature("increment()");
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("whitelistApp(address[],bool[])", apps, flags);

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        userOps = new UserOperation[](1);
        privateKeys = new uint256[](1);
        privateKeys[0] = _userPk; // we want to make use of the app key

        userOps[0] = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

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

    function testExecuteBatch_Revert_WhenUsingAppkey_WhenSignerIsAppKey_WhenLastOpIsWallet_Exploit() public {
        // deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);
        console.log("COUNTERRR", address(counter));
        console.log("WALLETTT", address(_kintoWallet));

        // fund paymaster for Counter contract
        _fundSponsorForApp(address(counter));

        // register app passing wallet as a child
        address[] memory appContracts = new address[](0);
        appContracts[0] = address(_kintoWallet);
        registerApp(_owner, "test", address(counter), appContracts);

        whitelistApp(address(counter));

        // set app key signature
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("setAppKey(address,address)", address(counter), _user),
            address(_paymaster)
        );
        _entryPoint.handleOps(userOps, payable(_owner));

        // prep batch
        address[] memory targets = new address[](3);
        targets[0] = address(counter);
        targets[1] = address(counter);
        targets[2] = address(_kintoWallet);

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        bytes[] memory calls = new bytes[](3);

        // whitelist app params
        address[] memory apps = new address[](1);
        apps[0] = address(counter);
        bool[] memory flags = new bool[](1);
        flags[0] = true;

        // 3 calls batch: whitelistApp and increment counter (two times)
        calls[0] = abi.encodeWithSignature("increment()");
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("whitelistApp(address[],bool[])", apps, flags);

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        userOps = new UserOperation[](1);
        privateKeys = new uint256[](1);
        privateKeys[0] = _userPk; // we want to make use of the app key

        userOps[0] = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        // send all transactions via batch
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 2);
    }
}

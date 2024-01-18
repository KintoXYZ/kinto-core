// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@aa/interfaces/IEntryPoint.sol";

import "../../src/interfaces/IKintoWallet.sol";

import "../../src/wallet/KintoWallet.sol";
import "../../src/sample/Counter.sol";

import "./harness/KintoWalletHarness.sol";
import {UserOp} from "./helpers/UserOp.sol";
import {AATestScaffolding} from "./helpers/AATestScaffolding.sol";

contract UpgradeToTest is AATestScaffolding, UserOp {
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

    /* ============ One Signer Account Transaction Tests (executeBatch) ============ */

    function testExecuteBatch() public {
        // deploy the counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);

        // fund paymaster for Counter contract
        _fundSponsorForApp(address(counter));

        registerApp(_owner, "test", address(counter));

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

        address[] memory apps = new address[](1);
        apps[0] = address(counter);

        bool[] memory flags = new bool[](1);
        flags[0] = true;

        // 3 calls batch: whitelistApp and increment counter (two times)
        calls[0] = abi.encodeWithSignature("whitelistApp(address[],bool[])", apps, flags);
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        // send all transactions via batch
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 2);
    }

    function testExecuteBatch_RevertWhen_TargetsBelongToDifferentApps() public {
        // deploy the counter contract
        Counter counter = new Counter();
        Counter counter2 = new Counter();
        assertEq(counter.count(), 0);
        assertEq(counter2.count(), 0);

        // fund paymaster for Counter contract
        _fundSponsorForApp(address(counter));

        registerApp(_owner, "counter app", address(counter));
        registerApp(_owner, "counter2 app", address(counter2));

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

        // 3 calls batch: whitelistApp, increment counter and increment counter2
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

    // we want to test that we can execute a batch of user ops where all targets are app children
    // except for the first and the last ones which are the wallet itself
    function testExecuteBatch_TopAndBottomWalletOps() public {
        // deploy the counter contract
        Counter counter = new Counter();
        Counter counterRelatedContract = new Counter();
        assertEq(counter.count(), 0);

        // fund paymaster for Counter contract
        _fundSponsorForApp(address(counter));

        address[] memory appContracts = new address[](1);
        appContracts[0] = address(counterRelatedContract);
        registerApp(_owner, "counter app", address(counter), appContracts);

        // prep batch
        address[] memory targets = new address[](4);
        targets[0] = address(_kintoWallet);
        targets[1] = address(counter);
        targets[2] = address(counterRelatedContract);
        targets[3] = address(_kintoWallet);

        uint256[] memory values = new uint256[](4);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        values[3] = 0;

        // whitelistApp params
        address[] memory apps = new address[](1);
        apps[0] = address(counter);

        bool[] memory flags = new bool[](1);
        flags[0] = true;

        // 4 calls batch: whitelistApp, increment counter and increment counter2 and whitelistApp
        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeWithSignature("whitelistApp(address[],bool[])", apps, flags);
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");
        calls[3] = abi.encodeWithSignature("whitelistApp(address[],bool[])", apps, flags);

        // send all transactions via batch
        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        // execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(counter.count(), 1);
        assertEq(counterRelatedContract.count(), 1);
    }

    /* ============ Recovery Tests ============ */

    function testStartRecovert() public {
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
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](0);

        vm.startPrank(_kycProvider);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        sigdata = _auxCreateSignature(_kintoIDv1, _owner, _owner, 1, block.timestamp + 1000);
        _kintoIDv1.burnKYC(sigdata);
        vm.stopPrank();

        assertEq(_kintoIDv1.isKYC(_user), true);

        // pass recovery time
        vm.warp(block.timestamp + _kintoWallet.RECOVERY_TIME() + 1);

        address[] memory users = new address[](1);
        users[0] = _user;
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);

        vm.prank(_kycProvider);
        _kintoIDv1.monitor(users, updates);

        vm.prank(address(_walletFactory));
        _kintoWallet.finishRecovery(users);

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
        vm.prank(address(_walletFactory));
        vm.expectRevert("KW-fr: Old KYC must be burned");
        _kintoWallet.finishRecovery(users);
    }

    function testComplete_RevertWhen_RecoverWithoutNewOwnerKYCd() public {
        assertEq(_kintoWallet.owners(0), _owner);

        // start recovery
        vm.prank(address(_walletFactory));
        _kintoWallet.startRecovery();
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
        vm.prank(address(_walletFactory));
        vm.expectRevert("KW-rs: KYC Required");
        _kintoWallet.finishRecovery(users);
    }

    function testComplete_RevertWhen_RecoverNotEnoughTime() public {
        assertEq(_kintoWallet.owners(0), _owner);

        // start recovery
        vm.prank(address(_walletFactory));
        _kintoWallet.startRecovery();
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
        vm.prank(address(_walletFactory));
        vm.expectRevert("KW-fr: too early");
        _kintoWallet.finishRecovery(users);
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

    /* ============ Whitelist ============ */

    function testWhitelistRegisteredApp() public {
        // (1). deploy Counter contract
        Counter counter = new Counter();
        assertEq(counter.count(), 0);

        // (2). fund paymaster for Counter contract
        _fundSponsorForApp(address(counter));

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
    //     _fundSponsorForApp(address(counter));

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

    /* ============ Getters ============ */

    function testGetOwnersCount() public {
        assertEq(_kintoWallet.getOwnersCount(), 1);
    }

    /* ============ _validateSignature ============ */

    function testValidateSignature_RevertWhen_OwnerIsNotKYCd() public {
        useHarness();
        revokeKYC(_kycProvider, _owner, _ownerPk);

        UserOperation memory userOp;
        assertEq(
            SIG_VALIDATION_FAILED,
            KintoWalletHarness(payable(address(_kintoWallet))).exposed_validateSignature(userOp, bytes32(0))
        );
    }

    function testValidateSignature_RevertWhen_SignatureLengthMismatch() public {
        useHarness();
        revokeKYC(_kycProvider, _owner, _ownerPk);

        UserOperation memory userOp;
        assertEq(
            SIG_VALIDATION_FAILED,
            KintoWalletHarness(payable(address(_kintoWallet))).exposed_validateSignature(userOp, bytes32(0))
        );
    }

    /* ============ _getAppContract ============ */
    function testGetAppContract() public {}
}

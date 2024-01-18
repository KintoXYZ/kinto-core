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
}

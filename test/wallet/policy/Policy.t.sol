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

contract ResetSignerTest is AATestScaffolding, UserOp {
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
}

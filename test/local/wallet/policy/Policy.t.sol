// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";

contract ResetSignerTest is SharedSetup {
    /* ============ Signers & Policy tests ============ */

    function testResetSigners_WhenAddingOneSigner() public {
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

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWallet.owners(1), _user);
        vm.stopPrank();
    }

    function testResetSigners_RevertWhen_DuplicateSigner() public {
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

        // @dev handleOps fails silently (does not revert)
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(IKintoWallet.DuplicateSigner.selector);
    }

    function testResetSigners_RevertWhen_EmptyArray() public {
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

        // @dev handleOps fails silently (does not revert)
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(IKintoWallet.EmptySigners.selector);
    }

    function testResetSigners_RevertWhen_ManyOwners() public {
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

        // @dev handleOps fails silently (does not revert)
        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(IKintoWallet.MaxSignersExceeded.selector);
    }

    function testResetSigners_RevertWhen_WithoutKYCSigner() public {
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

        _entryPoint.handleOps(userOps, payable(_owner));
    }

    function testResetSigners_WhenChangingPolicy_WhenTwoSigners() public {
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWallet.ALL_SIGNERS()),
            address(_paymaster)
        );

        vm.expectEmit();
        emit WalletPolicyChanged(_kintoWallet.ALL_SIGNERS(), _kintoWallet.SINGLE_SIGNER());
        _entryPoint.handleOps(userOps, payable(_owner));

        assertEq(_kintoWallet.owners(1), _user);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.ALL_SIGNERS());
    }

    function testResetSigners_WhenChangingPolicy_WhenThreeSigners() public {
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
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_kintoWallet.owners(1), _user);
        assertEq(_kintoWallet.owners(2), _user2);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.MINUS_ONE_SIGNER());
        vm.stopPrank();
    }

    function testResetSigners_RevertWhen_ChangingPolicy_WhenNotRightSigners() public {
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;

        // call setSignerPolicy with ALL_SIGNERS policy should revert because the wallet has 1 owners
        // and the policy requires 3 owners.
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("setSignerPolicy(uint8)", _kintoWallet.ALL_SIGNERS()),
            address(_paymaster)
        );

        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );

        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));

        assertRevertReasonEq(IKintoWallet.InvalidPolicy.selector);
        assertEq(_kintoWallet.owners(0), _owner);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.SINGLE_SIGNER());
    }

    function testResetSigners_RevertWhen_InvalidPolicy(uint256 policy) public {
        vm.assume(policy == 0 || policy > 3);

        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;

        // call setSignerPolicy with 0 policy
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("setSignerPolicy(uint8)", 0),
            address(_paymaster)
        );

        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );

        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));

        assertRevertReasonEq(IKintoWallet.InvalidPolicy.selector);
        assertEq(_kintoWallet.owners(0), _owner);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.SINGLE_SIGNER());
    }

    // todo: we technically allow this but the additional owners are ignored
    // function testResetSigners_RevertWhen_ChangingPolicy_WhenNotRightSigners_2() public {
    //     address[] memory owners = new address[](2);
    //     owners[0] = _owner;
    //     owners[1] = _user;

    //     // call resetSigners with existing policy (SINGLE_SIGNER) should revert because I'm passing 2 owners
    //     UserOperation[] memory userOps = new UserOperation[](1);
    //     userOps[0] = _createUserOperation(
    //         address(_kintoWallet),
    //         address(_kintoWallet),
    //         _kintoWallet.getNonce(),
    //         privateKeys,
    //         abi.encodeWithSignature("resetSigners(address[],uint8)", owners, _kintoWallet.signerPolicy()),
    //         address(_paymaster)
    //     );

    //     vm.expectEmit(true, true, true, false);
    //     emit UserOperationRevertReason(
    //         _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
    //     );

    //     vm.recordLogs();
    //     _entryPoint.handleOps(userOps, payable(_owner));

    //     assertRevertReasonEq("Address: low-level call with value failed");
    //     assertEq(_kintoWallet.owners(0), _owner);
    //     assertEq(_kintoWallet.signerPolicy(), _kintoWallet.SINGLE_SIGNER());
    // }
}

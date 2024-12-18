// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";

contract ResetSignerTest is SharedSetup {
    /* ============ Signers & Policy tests ============ */

    function testResetSigners_WhenAddingOneSigner() public {
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;

        vm.startPrank(address(_kintoWallet));
        _kintoWallet.resetSigners(owners, _kintoWallet.signerPolicy());
        vm.stopPrank();

        assertEq(_kintoWallet.owners(0), _owner);
        assertEq(_kintoWallet.owners(1), _user);
    }

    function testResetSigners_WhenRemovingOneSigner() public {
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;

        vm.startPrank(address(_kintoWallet));
        _kintoWallet.resetSigners(owners, _kintoWallet.signerPolicy());
        vm.stopPrank();

        owners = new address[](1);
        owners[0] = _owner;

        vm.startPrank(address(_kintoWallet));
        _kintoWallet.resetSigners(owners, _kintoWallet.signerPolicy());
        vm.stopPrank();

        assertEq(_kintoWallet.owners(0), _owner);
    }

    function testResetSigners_RevertWhen_DuplicateSigner() public {
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _owner;
        uint8 policy = _kintoWallet.signerPolicy();

        vm.prank(address(_kintoWallet));
        vm.expectRevert(abi.encodeWithSelector(IKintoWallet.DuplicateSigner.selector));
        _kintoWallet.resetSigners(owners, policy);
    }

    function testResetSigners_RevertWhen_EmptyArray() public {
        address[] memory owners = new address[](0);
        uint8 policy = _kintoWallet.signerPolicy();

        vm.prank(address(_kintoWallet));
        vm.expectRevert(abi.encodeWithSelector(IKintoWallet.EmptySigners.selector));
        _kintoWallet.resetSigners(owners, policy);
    }

    function testResetSigners_RevertWhen_ManyOwners() public {
        address[] memory owners = new address[](5);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user;
        owners[3] = _user;
        owners[4] = _user;
        uint8 policy = _kintoWallet.signerPolicy();

        vm.prank(address(_kintoWallet));
        vm.expectRevert(abi.encodeWithSelector(IKintoWallet.MaxSignersExceeded.selector, 5));
        _kintoWallet.resetSigners(owners, policy);
    }

    function testResetSigners_RevertWhen_WithoutKYCSigner() public {
        // I don't think it is possible to reach this error right now
        vm.skip(true);
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = address(1);
        uint8 policy = _kintoWallet.signerPolicy();

        vm.prank(address(_kintoWallet));
        vm.expectRevert(abi.encodeWithSelector(IKintoWallet.KYCRequired.selector));
        _kintoWallet.resetSigners(owners, policy);
    }

    function testResetSigners_WhenChangingPolicy_WhenTwoSigners() public {
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        uint8 policy = _kintoWallet.ALL_SIGNERS();

        vm.expectEmit();
        emit WalletPolicyChanged(_kintoWallet.ALL_SIGNERS(), _kintoWallet.SINGLE_SIGNER());
        vm.prank(address(_kintoWallet));
        _kintoWallet.resetSigners(owners, policy);

        assertEq(_kintoWallet.owners(1), _user);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.ALL_SIGNERS());
    }

    function testResetSigners_WhenChangingPolicy_WhenMinusOneSigner() public {
        address[] memory owners = new address[](3);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user2;
        uint8 policy = _kintoWallet.MINUS_ONE_SIGNER();

        vm.expectEmit();
        emit WalletPolicyChanged(_kintoWallet.MINUS_ONE_SIGNER(), _kintoWallet.SINGLE_SIGNER());
        vm.prank(address(_kintoWallet));
        _kintoWallet.resetSigners(owners, policy);

        assertEq(_kintoWallet.owners(0), _owner);
        assertEq(_kintoWallet.owners(1), _user);
        assertEq(_kintoWallet.owners(2), _user2);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.MINUS_ONE_SIGNER());
    }

    function testResetSigners_WhenChangingPolicy_WhenThreeSigners() public {
        address[] memory owners = new address[](3);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user2;
        uint8 policy = _kintoWallet.TWO_SIGNERS();

        vm.expectEmit();
        emit WalletPolicyChanged(_kintoWallet.TWO_SIGNERS(), _kintoWallet.SINGLE_SIGNER());
        vm.prank(address(_kintoWallet));
        _kintoWallet.resetSigners(owners, policy);

        assertEq(_kintoWallet.owners(1), _user);
        assertEq(_kintoWallet.owners(2), _user2);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.TWO_SIGNERS());
    }

    function testResetSigners_RevertWhen_ChangingPolicy_WhenNotRightSigners() public {
        // allows AllSigner for singe signer
        vm.skip(true);
        address[] memory owners = new address[](1);
        owners[0] = _owner;
        uint8 policy = _kintoWallet.ALL_SIGNERS();

        vm.prank(address(_kintoWallet));
        vm.expectRevert(abi.encodeWithSelector(IKintoWallet.InvalidPolicy.selector, 3, 1));
        _kintoWallet.resetSigners(owners, policy);
    }

    function testResetSigners_RevertWhen_InvalidPolicy() public {
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;

        vm.prank(address(_kintoWallet));
        vm.expectRevert(abi.encodeWithSelector(IKintoWallet.InvalidPolicy.selector, 0, 2));
        _kintoWallet.resetSigners(owners, 0);

        vm.prank(address(_kintoWallet));
        vm.expectRevert(abi.encodeWithSelector(IKintoWallet.InvalidPolicy.selector, 5, 2));
        _kintoWallet.resetSigners(owners, 5);
    }

    function testResetSignersWhen_ChangingSignersLength_WhenKeepingPolicy() public {
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        uint8 policy = _kintoWallet.SINGLE_SIGNER();

        vm.prank(address(_kintoWallet));
        _kintoWallet.resetSigners(owners, policy);

        assertEq(_kintoWallet.owners(0), _owner);
        assertEq(_kintoWallet.owners(1), _user);
        assertEq(_kintoWallet.signerPolicy(), _kintoWallet.SINGLE_SIGNER());
    }
}

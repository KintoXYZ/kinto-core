// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@aa/interfaces/IEntryPoint.sol";
import "@kinto-core/interfaces/IKintoWallet.sol";
import "@kinto-core/wallet/KintoWallet.sol";
import "@kinto-core/wallet/MultisigSigner.sol";
import "@kinto-core/sample/Counter.sol";

import "@kinto-core-test/helpers/BaseTest.sol";
import "@kinto-core-test/helpers/UserOp.sol";
import "@kinto-core-test/helpers/AATestScaffolding.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";

import "@kinto-core-test/SharedSetup.t.sol";

contract MultisigSignerTest is SharedSetup {
    using ECDSAUpgradeable for bytes32;

    MultisigSigner public multisig;
    uint8 public constant ALL_SIGNERS = 3;

    address[] public walletSigners;
    uint256 private nonce = 1;

    // Test operation parameters
    address public destination;
    uint256 public value = 0 ether;
    bytes public data = abi.encodeWithSignature("increment()");
    uint256 public expiresIn = 1 days;
    uint256 public threshold = 3;

    function setUp() public override {
        super.setUp();

        destination = address(counter);

        // Setup alice owners
        walletSigners = new address[](3);
        walletSigners[0] = alice0;
        walletSigners[1] = bob0;
        walletSigners[2] = hannah0;

        // Deploy implementation and proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(new MultisigSigner(_entryPoint)), abi.encodeCall(MultisigSigner.initialize, (_owner))
        );

        multisig = MultisigSigner(address(proxy));

        vm.prank(address(alice));
        IKintoWallet(alice).resetSigners(walletSigners, ALL_SIGNERS);

        whitelistApp(address(counter), true, address(alice));
    }

    function testUp() public view override {
        // Check owner is correctly set
        assertEq(multisig.owner(), _owner, "Owner not correctly set");
    }

    function testCreateOperation() public {
        vm.startPrank(alice0);

        // Create operation
        bytes32 opId = multisig.createOperation(address(alice), destination, value, data, expiresIn);

        // Get operation details
        (
            address wallet,
            address dest,
            uint256 val,
            bytes memory callData,
            uint256 nnc,
            uint256 thresh,
            uint256 expiresAt,
            bool executed,
            uint256 signatureCount
        ) = multisig.getOperation(opId);

        // Verify operation details
        assertEq(wallet, address(alice), "Wallet address mismatch");
        assertEq(dest, destination, "Destination address mismatch");
        assertEq(val, value, "Value mismatch");
        assertEq(bytes32(callData), bytes32(data), "Call data mismatch");
        assertEq(nnc, 0, "Nonce mismatch");
        assertEq(thresh, ALL_SIGNERS, "Threshold should match wallet policy");
        assertEq(expiresAt, block.timestamp + expiresIn, "Expiration time mismatch");
        assertFalse(executed, "Operation should not be executed");
        assertEq(signatureCount, 0, "Signature count should be 0");

        vm.stopPrank();
    }

    function testCreateOperation_RevertWhen_NotWalletOwner() public {
        vm.startPrank(eve); // Not a alice owner

        vm.expectRevert(abi.encodeWithSelector(MultisigSigner.NotWalletOwner.selector, address(alice), eve));
        multisig.createOperation(address(alice), destination, value, data, expiresIn);

        vm.stopPrank();
    }

    // Test removed as threshold is now determined from wallet policy

    function testAddSignature() public {
        vm.prank(alice0);
        // Create operation
        bytes32 opId = multisig.createOperation(address(alice), destination, value, data, expiresIn);

        // Get operation hash
        bytes32 messageHash = multisig.getOperationHash(opId);
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();

        // Sign with the second owner
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bob0Pk, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Add signature
        vm.prank(bob0);
        multisig.addSignature(opId, signature);

        // Check signature count
        (,,,,,,,, uint256 signatureCount) = multisig.getOperation(opId);
        assertEq(signatureCount, 1, "Signature count should be 1");
    }

    function testAddSignature_RevertWhen_NonExistentOperation() public {
        bytes32 invalidOpId = bytes32(uint256(1));
        bytes memory signature = new bytes(65);

        vm.prank(alice0);
        vm.expectRevert(abi.encodeWithSelector(MultisigSigner.OperationNotFound.selector, invalidOpId));
        multisig.addSignature(invalidOpId, signature);
    }

    function testAddSignatureAndExecute() public {
        vm.startPrank(alice0);

        // Fund the contract for potential gas costs
        vm.deal(address(alice), 1 ether);

        // Create operation
        bytes32 opId = multisig.createOperation(address(alice), destination, value, data, expiresIn);

        // First signature
        bytes32 messageHash = multisig.getOperationHash(opId);
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice0Pk, ethSignedMessageHash);
        bytes memory signature1 = abi.encodePacked(r, s, v);
        multisig.addSignature(opId, signature1);
        vm.stopPrank();

        // Second signature with execute
        (v, r, s) = vm.sign(bob0Pk, ethSignedMessageHash);
        bytes memory signature2 = abi.encodePacked(r, s, v);
        vm.prank(bob0);
        multisig.addSignature(opId, signature2);

        // Third signature with execute
        (v, r, s) = vm.sign(hannah0Pk, ethSignedMessageHash);
        bytes memory signature3 = abi.encodePacked(r, s, v);
        uint256 count = counter.count();
        vm.prank(hannah0);
        multisig.addSignatureAndExecute(opId, signature3);

        // Verify operation was executed
        assertEq(counter.count(), count + 1);

        // Check operation status
        (,,,,,,, bool opExecuted, uint256 signatureCount) = multisig.getOperation(opId);
        assertTrue(opExecuted, "Operation execution flag should be true");
        assertEq(signatureCount, 3, "Signature count should be 3");
    }

    function testAddSignatureAndExecute_RevertWhen_ThresholdNotReached() public {
        vm.startPrank(alice0);

        // Create operation
        bytes32 opId = multisig.createOperation(address(alice), destination, value, data, expiresIn);

        // First signature
        bytes32 messageHash = multisig.getOperationHash(opId);
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice0Pk, ethSignedMessageHash);
        bytes memory signature1 = abi.encodePacked(r, s, v);
        multisig.addSignature(opId, signature1);
        vm.stopPrank();

        // Second signature with attempt to execute - should revert
        (v, r, s) = vm.sign(bob0Pk, ethSignedMessageHash);
        bytes memory signature2 = abi.encodePacked(r, s, v);

        vm.startPrank(bob0);

        // Now try to execute with 2 signatures when 3 are required
        vm.expectRevert(abi.encodeWithSelector(MultisigSigner.InsufficientSignatures.selector, opId, 2, 3));
        multisig.addSignatureAndExecute(opId, signature2);
        vm.stopPrank();

        // Check operation status - should not be executed
        (,,,,,,, bool opExecuted, uint256 signatureCount) = multisig.getOperation(opId);
        assertFalse(opExecuted, "Operation execution flag should be false");
        assertEq(signatureCount, 1, "Signature count should be 1");
    }

    function testExecuteOperation() public {
        vm.startPrank(alice0);

        // Fund the contract for potential gas costs
        vm.deal(address(alice), 1 ether);

        // Create operation
        bytes32 opId = multisig.createOperation(address(alice), destination, value, data, expiresIn);

        // First signature
        bytes32 messageHash = multisig.getOperationHash(opId);
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice0Pk, ethSignedMessageHash);
        bytes memory signature1 = abi.encodePacked(r, s, v);
        multisig.addSignature(opId, signature1);
        vm.stopPrank();

        // Second signature
        (v, r, s) = vm.sign(bob0Pk, ethSignedMessageHash);
        bytes memory signature2 = abi.encodePacked(r, s, v);
        vm.prank(bob0);
        multisig.addSignature(opId, signature2);

        // Third signature
        (v, r, s) = vm.sign(hannah0Pk, ethSignedMessageHash);
        bytes memory signature3 = abi.encodePacked(r, s, v);
        vm.prank(hannah0);
        multisig.addSignature(opId, signature3);

        // Execute operation
        uint256 count = counter.count();
        vm.prank(alice0);
        multisig.executeOperation(opId);

        // Verify operation was executed
        assertEq(counter.count(), count + 1);

        // Check operation status
        (,,,,,,, bool opExecuted, uint256 signatureCount) = multisig.getOperation(opId);
        assertTrue(opExecuted, "Operation execution flag should be true");
        assertEq(signatureCount, 3, "Signature count should be 3");

        // Clean up the mock
        vm.clearMockedCalls();
    }

    function testExecuteOperation_RevertWhen_InsufficientSignatures() public {
        // Create operation
        vm.prank(alice0);
        bytes32 opId = multisig.createOperation(address(alice), destination, value, data, expiresIn);

        // Add only one signature when 3 are required
        bytes32 messageHash = multisig.getOperationHash(opId);
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice0Pk, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.prank(alice0);
        multisig.addSignature(opId, signature);

        // Try to execute with insufficient signatures
        vm.prank(alice0);
        vm.expectRevert(abi.encodeWithSelector(MultisigSigner.InsufficientSignatures.selector, opId, 1, 3));
        multisig.executeOperation(opId);
    }

    function testCancelOperation() public {
        // Create operation with one of alice's owners (alice0)
        vm.startPrank(alice0);
        bytes32 opId = multisig.createOperation(address(alice), destination, value, data, expiresIn);
        vm.stopPrank();

        // Get operation details before cancellation
        (address walletBefore,,,,,,,,) = multisig.getOperation(opId);
        assertEq(walletBefore, address(alice), "Operation should exist before cancellation");

        // Cancel operation as contract owner
        vm.prank(_owner);
        multisig.cancelOperation(opId);

        // Check operation details after cancellation
        (address walletAfter,,,,,,,,) = multisig.getOperation(opId);
        assertEq(walletAfter, address(0), "Operation should be deleted after cancellation");
    }

    function testCancelOperation_RevertWhen_CalledByNonOwner() public {
        // Create operation with one of alice's owners (alice0)
        vm.startPrank(alice0);
        bytes32 opId = multisig.createOperation(address(alice), destination, value, data, expiresIn);
        vm.stopPrank();

        // Try to cancel from non-owner
        vm.prank(hannah);
        vm.expectRevert("Ownable: caller is not the owner");
        multisig.cancelOperation(opId);
    }
}

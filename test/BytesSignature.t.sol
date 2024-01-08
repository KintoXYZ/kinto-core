// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "../src/libraries/ByteSignature.sol";
import {UserOp} from "./helpers/UserOp.sol";

contract ByteSignatureTest is UserOp {
    function testExtractSingleSignature() public {
        // dummy signature
        bytes memory signature =
            hex"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff01";
        bytes[] memory extracted = ByteSignature.extractSignatures(signature, 1);
        assertEq(extracted[0], signature, "The extracted signature does not match the original signature.");
    }

    function testExtractMultipleSignatures() public {
        // create 2 dummy signatures
        bytes memory signature1 =
            hex"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff01";
        bytes memory signature2 =
            hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1c";
        bytes memory fullSignature = abi.encodePacked(signature1, signature2);

        bytes[] memory extracted = ByteSignature.extractSignatures(fullSignature, 2);
        assertEq(extracted[0], signature1, "The first signature does not match the original signature.");
        assertEq(extracted[1], signature2, "The second signature does not match the original signature.");
    }

    function testFuzzExtractMultipleSignatures(uint8 numSignatures) public {
        bytes memory fullSignature;
        bytes[] memory originalSignatures = new bytes[](numSignatures);

        // generate random signatures
        for (uint8 i = 0; i < numSignatures;i++) {
            bytes memory signature = new bytes(65);
            for (uint256 j = 0; j < 65; j++) {
                signature[j] = bytes1(uint8(uint256(keccak256(abi.encodePacked(block.timestamp, i, j))) % 256));
            }
            fullSignature = abi.encodePacked(fullSignature, signature);
            originalSignatures[i] = signature;
        }

        bytes[] memory extracted = ByteSignature.extractSignatures(fullSignature, numSignatures);

        for (uint8 i = 0; i < numSignatures; i++) {
            assertEq(extracted[i], originalSignatures[i], "Signature does not match the original signature.");
        }
    }

    function testExtract_RevertWhen_InvalidLength() public {
        bytes memory invalidSignature = hex"abcd";
        vm.expectRevert("ByteSignature: Invalid signature length");
        ByteSignature.extractSignatures(invalidSignature, 1);
    }
}

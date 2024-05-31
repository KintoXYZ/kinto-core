// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {LibString} from "solady/utils/LibString.sol";

import "@aa/interfaces/IEntryPoint.sol";
import "@aa/core/EntryPoint.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "@kinto-core/wallet/KintoWallet.sol";
import "@kinto-core/wallet/KintoWalletFactory.sol";

import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import {Script} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

abstract contract SignerHelper is Test {
    using ECDSAUpgradeable for bytes32;
    using LibString for *;

    function signWithHW(uint256 hwType, bytes32 hash) internal returns (bytes memory signature) {
        string memory hashString = toHexString(hash);

        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = string.concat("cast wallet sign ", hwType == 0 ? "--ledger " : "--trezor ", hashString);

        signature = vm.ffi(inputs);
        if (signature.length != 65) {
            console2.log("Error: %s", string(signature));
        }

        console2.log("\nSignature:");
        console2.logBytes(signature);

        signature = makeEIP191Compliant(signature);

        (address signer,) = ECDSAUpgradeable.tryRecover(hash.toEthSignedMessageHash(), signature);
        console2.log("signer:", signer);
    }

    function toHexString(bytes32 data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            str[i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
            str[1 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
        }
        return string.concat("0x", string(str));
    }

    // Change `v` value to 1B (27) or 1C (28) for EIP-191 compliance
    // @dev If last byte of the signature is 0/1/4 then covert it to the EIP-191 standard
    function makeEIP191Compliant(bytes memory signature) internal pure returns (bytes memory) {
        // check the signature length
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        // extract r, s and v variables.
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        // if the version is correct return the signer address
        if (v < 27) {
            // if v is 0 or 1, add 27 to convert it to 27 or 28
            if (v == 0) v = 28;
            if (v == 4) v = 28;
            if (v == 1) v = 27;
        } else {
            return signature;
        }

        // reconstruct the signature with the correct v value
        bytes memory newSignature = abi.encodePacked(r, s, v);

        return newSignature;
    }
}

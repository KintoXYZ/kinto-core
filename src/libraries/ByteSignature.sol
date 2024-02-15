// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

library ByteSignature {
    error InvalidSignatureLength();

    function extractSignatures(bytes memory _fullSignature, uint256 count)
        internal
        pure
        returns (bytes[] memory signatures)
    {
        if (_fullSignature.length < count * 65) revert InvalidSignatureLength();
        signatures = new bytes[](count);
        for (uint256 i = 0; i < count; i++) {
            signatures[i] = extractECDASignatureFromBytes(_fullSignature, i);
        }
    }

    function extractECDASignatureFromBytes(bytes memory _fullSignature, uint256 position)
        internal
        pure
        returns (bytes memory signature)
    {
        uint256 offset = (position * 0x40) + position;
        signature = new bytes(65);
        // Copying the first signature. Note, that we need an offset of 0x20
        // since it is where the length of the `_fullSignature` is stored
        assembly {
            let r := mload(add(_fullSignature, add(offset, 0x20)))
            let s := mload(add(_fullSignature, add(offset, 0x40)))
            let v := and(mload(add(_fullSignature, add(offset, 0x41))), 0xff)

            mstore(add(signature, 0x20), r)
            mstore(add(signature, 0x40), s)
            mstore8(add(signature, 0x60), v)
        }
    }
}

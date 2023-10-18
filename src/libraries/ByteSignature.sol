// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

library ByteSignature {
  function extractTwoSignatures(bytes memory _fullSignature)
      internal pure
      returns (bytes memory signature1, bytes memory signature2) {
      signature1 = new bytes(65);
      signature2 = new bytes(65);
      return (extractECDASignatureFromBytes(_fullSignature, 0),
        extractECDASignatureFromBytes(_fullSignature, 1));
  }

  function extractThreeSignatures(bytes memory _fullSignature)
      internal pure returns (bytes memory signature1, bytes memory signature2, bytes memory signature3) {
      signature1 = new bytes(65);
      signature2 = new bytes(65);
      signature3 = new bytes(65);
      return (extractECDASignatureFromBytes(_fullSignature, 0),
          extractECDASignatureFromBytes(_fullSignature, 1),
          extractECDASignatureFromBytes(_fullSignature, 2));
  }

  function extractECDASignatureFromBytes(bytes memory _fullSignature, uint position)
      internal pure returns (bytes memory signature) {
      signature = new bytes(65);
      // Copying the first signature. Note, that we need an offset of 0x20
      // since it is where the length of the `_fullSignature` is stored
      uint firstIndex = (position * 0x40) + 0x20 + position;
      uint secondIndex = (position * 0x40) + 0x40 + position;
      uint thirdIndex = (position * 0x40) + 0x41 + position;
      assembly {
          let r := mload(add(_fullSignature, firstIndex))
          let s := mload(add(_fullSignature, secondIndex))
          let v := and(mload(add(_fullSignature, thirdIndex)), 0xff)

          mstore(add(signature, 0x20), r)
          mstore(add(signature, 0x40), s)
          mstore8(add(signature, 0x60), v)
      }
  }
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract BytesLibMock {
    struct RSV {
        bytes32 r;
        bytes32 s;
        uint8 v;
    }
    /// Full signature hash => position => RSV
    mapping(bytes32 => mapping(uint256 => RSV)) private _extractSig;

    function extractSignature(bytes32 signatureHash, uint256 position) external view returns (bytes memory) {
        RSV storage _rsv = _extractSig[signatureHash][position];
        bytes memory sig = abi.encodePacked(_rsv.r,_rsv.s,_rsv.v);
        return sig;
    }
}

contract MockECDSA {

    mapping(bytes32 => mapping(bytes32 => address)) private _recover;

    function recoverMock(bytes32 hash, bytes memory signature) external view returns (address signer) {
        require (signature.length == 65, "Invalid signature length");
        bytes32 sigHash = keccak256(abi.encode(signature));
        signer = _recover[hash][sigHash];
        
        // If the signature is valid (and not malleable), return the signer address
        if (signer == address(0)) {
            revert("InvalidSignature");
        }

        return signer;
    }
}
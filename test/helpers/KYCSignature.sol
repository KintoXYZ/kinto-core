// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '../../src/KintoID.sol';
import '../../src/interfaces/IKintoID.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
import {SignatureChecker} from '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';

import 'forge-std/Test.sol';
import 'forge-std/console.sol';

abstract contract KYCSignature is Test {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    // Create a test for minting a KYC token
    function _auxCreateSignature(IKintoID _kintoIDv1, address _signer, address _account, uint256 _privateKey, uint256 _expiresAt) internal view returns (
        IKintoID.SignatureData memory signData
    ) {
        bytes32 dataHash = keccak256(
            abi.encode(
                _signer,
                address(_kintoIDv1),
                _account,
                _kintoIDv1.KYC_TOKEN_ID(),
                _expiresAt,
                _kintoIDv1.nonces(_signer),
                bytes32(block.chainid)
            ));
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0x01),
                dataHash
            )
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        return IKintoID.SignatureData(
                _signer,
                _account,
                _kintoIDv1.nonces(_signer),
                _expiresAt,
                signature
            );
    }

    function _auxDappSignature(IKintoID _kintoIDv1, IKintoID.SignatureData memory signData) internal view returns (bool) {
        bytes32 dataHash = keccak256(abi.encode(
            signData.signer,
            0xa8bEb41Cf4721121ea58837eBDbd36169a7F246E,
            signData.account,
            _kintoIDv1.KYC_TOKEN_ID(),
            signData.expiresAt,
            _kintoIDv1.nonces(signData.signer),
            bytes32(block.chainid)
        ));
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0x01),
                dataHash
            )
        );
        hash = hash.toEthSignedMessageHash();
        // uint256 key = vm.envUint("FRONTEND_KEY");
        uint256 key = 1;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, hash);
        bytes memory newsignature = abi.encodePacked(r, s, v);
        bool valid = signData.signer.isValidSignatureNow(hash, newsignature);
        return valid;
    }
}
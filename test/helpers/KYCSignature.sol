// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@oz/contracts/utils/cryptography/MessageHashUtils.sol";
import "@oz/contracts/utils/cryptography/SignatureChecker.sol";

import "../../src/KintoID.sol";
import "../../src/interfaces/IKintoID.sol";
import "../../src/interfaces/IFaucet.sol";
import "../../src/interfaces/IBridger.sol";

abstract contract KYCSignature is Test {
    using MessageHashUtils for bytes32;
    using SignatureChecker for address;

    // Create a test for minting a KYC token
    function _auxCreateSignature(IKintoID _kintoID, address _signer, uint256 _privateKey, uint256 _expiresAt)
        internal
        view
        returns (IKintoID.SignatureData memory signData)
    {
        signData = IKintoID.SignatureData({
            signer: _signer,
            nonce: _kintoID.nonces(_signer),
            expiresAt: _expiresAt,
            signature: ""
        });

        // generate EIP-712 hash
        bytes32 eip712Hash = _getEIP712Message(signData, address(_kintoID));

        // sign the hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, eip712Hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // update & return SignatureData
        signData.signature = signature;
        return signData;
    }

    // Create a aux function to create an EIP-191 compliant signature for claiming Kinto ETH from the faucet
    function _auxCreateSignature(IFaucet _faucet, address _signer, uint256 _privateKey, uint256 _expiresAt)
        internal
        view
        returns (IFaucet.SignatureData memory signData)
    {
        bytes32 dataHash = keccak256(
            abi.encode(_signer, address(_faucet), _expiresAt, _faucet.nonces(_signer), bytes32(block.chainid))
        );
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash)); // EIP-191 compliant

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        return IFaucet.SignatureData(_signer, _faucet.nonces(_signer), _expiresAt, signature);
    }

    // Create a aux function to create an EIP-191 compliant signature for claiming Kinto ETH from the faucet
    function _auxCreateBridgeSignature(
        IBridger _bridger,
        address _signer,
        address _inputAsset,
        uint256 _amount,
        address _finalAsset,
        uint256 _privateKey,
        uint256 _expiresAt
    ) internal view returns (IBridger.SignatureData memory signData) {
        uint256 nonce = _bridger.nonces(_signer);
        bytes32 dataHash = keccak256(
            abi.encode(_signer, address(_bridger), _inputAsset, _amount, _expiresAt, nonce, bytes32(block.chainid))
        );
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash)); // EIP-191 compliant

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        return IBridger.SignatureData(_signer, _inputAsset, _amount, _finalAsset, nonce, _expiresAt, signature);
    }

    function _auxDappSignature(IKintoID _kintoID, IKintoID.SignatureData memory signData)
        internal
        view
        returns (bool)
    {
        bytes32 dataHash = keccak256(
            abi.encode(
                signData.signer,
                0xa8bEb41Cf4721121ea58837eBDbd36169a7F246E,
                1,
                signData.expiresAt,
                _kintoID.nonces(signData.signer),
                bytes32(block.chainid)
            )
        );
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), dataHash));
        hash = hash.toEthSignedMessageHash();
        // uint256 key = vm.envUint("FRONTEND_KEY");
        uint256 key = 1;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, hash);
        bytes memory newsignature = abi.encodePacked(r, s, v);
        bool valid = signData.signer.isValidSignatureNow(hash, newsignature);
        return valid;
    }

    /* ============ EIP-712 Helpers ============ */

    function _getEIP712Message(IKintoID.SignatureData memory signatureData, address contractInstance)
        internal
        view
        returns (bytes32)
    {
        bytes32 domainSeparator = _domainSeparator(contractInstance);
        bytes32 structHash = _hashSignatureData(signatureData);
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _domainSeparator(address contractInstance) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("KintoID")), // this contract's name
                keccak256(bytes("1")), // version
                _getChainID(),
                contractInstance // kintoID contract address
            )
        );
    }

    function _getChainID() internal view returns (uint256) {
        uint256 chainID;
        assembly {
            chainID := chainid()
        }
        return chainID;
    }

    function _hashSignatureData(IKintoID.SignatureData memory signatureData) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("SignatureData(address signer,uint256 nonce,uint256 expiresAt)"),
                signatureData.signer,
                signatureData.nonce,
                signatureData.expiresAt
            )
        );
    }
}

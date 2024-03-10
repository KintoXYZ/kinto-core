// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "../../src/KintoID.sol";
import "../../src/interfaces/IKintoID.sol";
import "../../src/interfaces/IFaucet.sol";
import "../../src/interfaces/IBridger.sol";

abstract contract TestSignature is Test {
    using ECDSAUpgradeable for bytes32;
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
        bytes32 eip712Hash = _getEIP712Message(signData, _kintoID.domainSeparator());

        // sign the hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, eip712Hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // update & return SignatureData
        signData.signature = signature;
        return signData;
    }

    // Create a aux function to create an EIP-191 compliant signature for claiming Kinto ETH from the faucet
    function _auxCreateBridgeSignature(
        address kintoWalletL2,
        IBridger.SwapParams memory _swapParams,
        IBridger _bridger,
        address _signer,
        address _inputAsset,
        uint256 _amount,
        address _finalAsset,
        uint256 _privateKey,
        uint256 _expiresAt
    ) internal view returns (IBridger.SignatureData memory signData) {
        signData = IBridger.SignatureData({
            kintoWallet: kintoWalletL2,
            signer: _signer,
            inputAsset: _inputAsset,
            finalAsset: _finalAsset,
            amount: _amount,
            nonce: _bridger.nonces(_signer),
            expiresAt: _expiresAt,
            signature: "",
            swapParams: _swapParams
        });

        // generate EIP-712 hash
        bytes32 eip712Hash = _getBridgerMessage(signData, _bridger.domainSeparator());

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

    function _auxCreatePermitSignature(IBridger.Permit memory _permit, uint256 _privateKey, ERC20Permit _asset)
        internal
        view
        returns (bytes memory signature)
    {
        bytes32 domainSeparator;
        if (keccak256(abi.encodePacked(_asset.symbol())) == keccak256(abi.encodePacked("UNI"))) {
            bytes32 DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
            domainSeparator =
                keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(_asset.name())), block.chainid, address(_asset)));
        } else {
            domainSeparator = _asset.DOMAIN_SEPARATOR();
        }
        bytes32 eip712Hash = _getPermitMessage(vm.addr(_privateKey), _asset, _permit, domainSeparator);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, eip712Hash);
        signature = abi.encodePacked(r, s, v);
    }

    /* ============ EIP-712 Helpers ============ */

    function _getEIP712Message(IKintoID.SignatureData memory signatureData, bytes32 domainSeparator)
        internal
        pure
        returns (bytes32)
    {
        bytes32 structHash = _hashSignatureData(signatureData);
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _getPermitMessage(
        address holder,
        ERC20Permit _asset,
        IBridger.Permit memory permit,
        bytes32 domainSeparator
    ) internal view returns (bytes32) {
        bytes32 PERMIT_TYPEHASH;
        bytes32 structHash;
        if (keccak256(abi.encodePacked(_asset.symbol())) == keccak256(abi.encodePacked("DAI"))) {
            console.log("RERERE");
            PERMIT_TYPEHASH =
                keccak256("Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)");
            console.logBytes32(PERMIT_TYPEHASH);
            structHash =
                keccak256(abi.encode(PERMIT_TYPEHASH, holder, permit.spender, permit.nonce, permit.deadline, true));
        } else {
            PERMIT_TYPEHASH =
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
            structHash = keccak256(
                abi.encode(PERMIT_TYPEHASH, permit.owner, permit.spender, permit.value, permit.nonce, permit.deadline)
            );
        }

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _getBridgerMessage(IBridger.SignatureData memory signatureData, bytes32 domainSeparator)
        internal
        pure
        returns (bytes32)
    {
        bytes32 structHash = _hashSignatureData(signatureData);
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
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

    function _hashSignatureData(IBridger.SignatureData memory signatureData) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256(
                    "SignatureData(address signer,address inputAsset,uint256 amount,address finalAsset,uint256 nonce,uint256 expiresAt)"
                ),
                signatureData.signer,
                signatureData.inputAsset,
                signatureData.amount,
                signatureData.finalAsset,
                signatureData.nonce,
                signatureData.expiresAt
            )
        );
    }
}

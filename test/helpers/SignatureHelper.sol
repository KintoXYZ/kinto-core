// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {CommonBase} from "forge-std/Base.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "@kinto-core/KintoID.sol";
import "@kinto-core/interfaces/IKintoID.sol";
import "@kinto-core/interfaces/IFaucet.sol";
import "@kinto-core/interfaces/bridger/IBridger.sol";

abstract contract SignatureHelper is CommonBase {
    using SignatureChecker for address;

    bytes32 public constant _PERMIT_SINGLE_TYPEHASH = keccak256(
        "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
    );

    bytes32 public constant _PERMIT_DETAILS_TYPEHASH =
        keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)");

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
        IBridger _bridger,
        address _signer,
        address _inputAsset,
        address _finalAsset,
        uint256 _amount,
        uint256 _minReceive,
        uint256 _privateKey,
        uint256 _expiresAt
    ) internal view returns (IBridger.SignatureData memory signData) {
        signData = IBridger.SignatureData({
            kintoWallet: kintoWalletL2,
            signer: _signer,
            inputAsset: _inputAsset,
            finalAsset: _finalAsset,
            amount: _amount,
            minReceive: _minReceive,
            nonce: _bridger.nonces(_signer),
            expiresAt: _expiresAt,
            signature: ""
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

    // An aux function to create an EIP-191 compliant signature for Permit2.
    function _auxPermit2Signature(
        IAllowanceTransfer.PermitSingle memory permit,
        uint256 privateKey,
        bytes32 domainSeparator
    ) internal pure returns (bytes memory) {
        bytes32 permitHash = keccak256(abi.encode(_PERMIT_DETAILS_TYPEHASH, permit.details));

        bytes32 eip712Hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(abi.encode(_PERMIT_SINGLE_TYPEHASH, permitHash, permit.spender, permit.sigDeadline))
            )
        );

        // sign the hash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, eip712Hash);
        return abi.encodePacked(r, s, v);
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
        bytes32 symbol = keccak256(abi.encodePacked(_asset.symbol()));
        if (symbol == keccak256(abi.encodePacked("UNI"))) {
            bytes32 DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
            domainSeparator =
                keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(_asset.name())), block.chainid, address(_asset)));
        } else if (symbol == keccak256(abi.encodePacked("weETH"))) {
            bytes32 DOMAIN_TYPEHASH =
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
            domainSeparator = keccak256(
                abi.encode(
                    DOMAIN_TYPEHASH,
                    keccak256(bytes("EtherFi wrapped ETH")),
                    keccak256(bytes("1")),
                    block.chainid,
                    address(_asset)
                )
            );
        } else {
            // "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract"
            domainSeparator = _asset.DOMAIN_SEPARATOR();
        }
        bytes32 structHash = _getStructHash(vm.addr(_privateKey), _asset, _permit);
        bytes32 eip712Hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

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

    function _getStructHash(address holder, ERC20Permit _asset, IBridger.Permit memory permit)
        internal
        view
        returns (bytes32)
    {
        bytes32 PERMIT_TYPEHASH;
        bytes32 structHash;
        // DAI has special permit signature on Ethereum
        if (block.chainid == 1 && keccak256(abi.encodePacked(_asset.symbol())) == keccak256(abi.encodePacked("DAI"))) {
            PERMIT_TYPEHASH =
                keccak256("Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)");
            structHash =
                keccak256(abi.encode(PERMIT_TYPEHASH, holder, permit.spender, permit.nonce, permit.deadline, true));
        } else {
            PERMIT_TYPEHASH =
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
            structHash = keccak256(
                abi.encode(PERMIT_TYPEHASH, permit.owner, permit.spender, permit.value, permit.nonce, permit.deadline)
            );
        }
        return structHash;
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
                    "SignatureData(address kintoWallet,address signer,address inputAsset,uint256 amount,uint256 minReceive,address finalAsset,uint256 nonce,uint256 expiresAt)"
                ),
                signatureData.kintoWallet,
                signatureData.signer,
                signatureData.inputAsset,
                signatureData.amount,
                signatureData.minReceive,
                signatureData.finalAsset,
                signatureData.nonce,
                signatureData.expiresAt
            )
        );
    }
}

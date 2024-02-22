// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IKintoWalletFactory} from "./IKintoWalletFactory.sol";

interface IFaucet {
    /* ============ Errors ============ */
    error OnlyOwner();
    error SignatureExpired();
    error InvalidNonce();
    error InvalidSigner();

    /* ============ Structs ============ */

    struct SignatureData {
        address signer;
        address signerKintoWallet;
        address depositAsset;
        uint256 amount;
        address asset;
        uint256 nonce;
        uint256 expiresAt;
        bytes signature;
        //0x
        address spender;
        address swapTarget;
        address swapCallData;

        bytes permitSignature;
    }

    /* ============ State Change ============ */

    function deposit(address asset, uint256 amount) external;

    function depositBySig(SignatureData calldata _signatureData) external;

    /* ============ Basic Viewers ============ */


    function nonces(address _account) external view returns (uint256);

}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IKintoWalletFactory} from "./IKintoWalletFactory.sol";

interface IBridger {
    /* ============ Errors ============ */
    error OnlySender();
    error OnlyOwner();
    error SignatureExpired();
    error InvalidNonce();
    error InvalidSigner();

    /* ============ Structs ============ */

    struct SignatureData {
        address signer;
        address inputAsset;
        uint256 amount;
        address finalAsset;
        uint256 nonce;
        uint256 expiresAt;
        bytes signature;
    }

    struct SwapData {
        address spender;
        address swapTarget;
        bytes swapCallData;
    }

    /* ============ State Change ============ */

    function depositETH(
        address _kintoWallet,
        address _finalAsset,
        SwapData calldata _swapData
    ) external payable;

    function depositBySig(
        address _kintoWallet,
        SignatureData calldata _signatureData,
        SwapData calldata _swapData,
        bytes calldata _permitSignature
    ) external;

    function bridgeDeposits(address asset, uint256 maxGas, uint256 gasPriceBid, uint256 maxSubmissionCost) external;

    /* ============ Basic Viewers ============ */

    function deposits(address _account, address _asset) external view returns (uint256);

    function nonces(address _account) external view returns (uint256);
}

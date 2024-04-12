// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IKintoWalletFactory} from "./IKintoWalletFactory.sol";

interface IFaucet {
    /* ============ Errors ============ */
    error OnlyOwner();
    error OnlyFactory();
    error NotEnoughETH();
    error FaucetNotActive();
    error AlreadyClaimed();
    error SignatureExpired();
    error InvalidNonce();
    error InvalidSigner();

    /* ============ Structs ============ */

    struct SignatureData {
        address signer;
        uint256 nonce;
        uint256 expiresAt;
        bytes signature;
    }

    /* ============ State Change ============ */

    function claimKintoETH() external;

    function claimKintoETH(SignatureData calldata _signatureData) external;

    function withdrawAll() external;

    function startFaucet() external payable;

    /* ============ Basic Viewers ============ */

    function claimed(address _account) external view returns (bool);

    function nonces(address _account) external view returns (uint256);

    function walletFactory() external view returns (IKintoWalletFactory);
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/utils/structs/BitMapsUpgradeable.sol";

interface IFaucet {

    /* ============ Structs ============ */

    struct SignatureData {
        address signer;
        uint256 nonce;
        uint256 expiresAt;
        bytes signature;
    }

    /* ============ State Change ============ */

    function claimKintoETH() external;

    function withdrawAll() external;

    function startFaucet() payable external;

    /* ============ Basic Viewers ============ */

    function claimed(address _account) external view returns (bool);

    function nonces(address _account) external view returns (uint256);
}
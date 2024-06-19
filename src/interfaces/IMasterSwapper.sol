// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IMasterSwapper {
    /* ============ Errors ============ */
    error OnlyOwner();
    error OnlyRelayer();

    /* ============ Structs ============ */

    struct SwapInfo {
        address sender;
        address sellAsset;
        uint256 sellAmount;
        address buyAsset;
        uint26 minBuyAmount;
        uint256 deadline;
        bool completed;
    }

    /* ============ Basic Viewers ============ */

    /* ============ Constants and attrs ============ */
}

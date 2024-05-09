// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title IViewer
 */
interface IViewer {
    /* ============ Errors ============ */

    /* ============ Structs ============ */

    /* ============ View ============ */
    function getBalances(address[] memory tokens, address target) external view returns (uint256[] memory balances);

    /* ============ Constants ============ */
}

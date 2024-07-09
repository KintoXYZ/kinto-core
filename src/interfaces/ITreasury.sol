// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ITreasury {
    /* ============ Errors ============ */
    error OnlyOwner();

    /* ============ Functions ============ */

    function sendTreasuryFunds(address _asset, uint256 _amount, address _to) external;

    function sendTreasuryETH(uint256 _amount, address payable _to) external;

    function batchSendTreasuryFunds(address[] memory _assets, uint256[] memory _amounts, address[] memory _tos)
        external;
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IBridgerL2 {
    /* ============ Errors ============ */
    error OnlyOwner();
    error InvalidWallet();
    error NotUNlockedYet();

    /* ============ Structs ============ */


    /* ============ State Change ============ */

    function writeL2Deposit(address depositor, address assetL2, uint256 amount) external;

    function unlockCommitments() external;

    function claimCommitment(address kintoWallet) external;

    /* ============ Basic Viewers ============ */

    function deposits(address _account, address _asset) external view returns (uint256);

    function depositTotals(address _asset) external view returns (uint256);

    function depositCount() external view returns (uint256);

    function getUserDeposits() external view returns (uint256[] amounts);
    
    function getTotalDeposits() external view returns (uint256[] amounts);

    function unlocked() external view returns (bool);
}

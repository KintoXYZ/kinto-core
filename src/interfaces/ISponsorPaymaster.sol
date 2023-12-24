// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ISponsorPaymaster {

    /* ============ Structs ============ */

    // A structure to hold rate limiting data
    struct RateLimitData {
        uint256 lastOperationTime;
        uint256 operationCount;
    }

    /* ============ State Change ============ */

    function initialize(address owner) external;

    function addDepositFor(address account) payable external;

    function withdrawTokensTo(address target, uint256 amount) external;

    function unlockTokenDeposit() external;
    
    function lockTokenDeposit() external;

    /* ============ Basic Viewers ============ */

    function depositInfo(address account) external view returns (uint256 amount, uint256 _unlockBlock);

    /* ============ Constants and attrs ============ */

    function balances(address account) external view returns (uint256 amount);
    
    function contractSpent(address account) external view returns (uint256 amount);
    
    function unlockBlock(address account) external view returns (uint256 block);

}

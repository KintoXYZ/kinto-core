// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IKintoAppRegistry} from "./IKintoAppRegistry.sol";

interface ISponsorPaymaster {
    /* ============ Structs ============ */

    // A structure to hold rate limiting data
    struct RateLimitData {
        uint256 lastOperationTime;
        uint256 operationCount;
        uint256 ethCostCount;
    }

    /* ============ State Change ============ */

    function initialize(address owner) external;

    function setAppRegistry(address _appRegistry) external;

    function addDepositFor(address account) external payable;

    function withdrawTokensTo(address target, uint256 amount) external;

    function unlockTokenDeposit() external;

    function lockTokenDeposit() external;

    /* ============ Basic Viewers ============ */

    function depositInfo(address account) external view returns (uint256 amount, uint256 _unlockBlock);

    /* ============ Constants and attrs ============ */

    function balances(address account) external view returns (uint256 amount);

    function appRegistry() external view returns (IKintoAppRegistry);

    function contractSpent(address account) external view returns (uint256 amount);

    function unlockBlock(address account) external view returns (uint256 block);

    function appUserLimit(address user, address app) external view returns (uint256, uint256, uint256, uint256);
}

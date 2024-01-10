// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {IKintoWalletFactory} from "./IKintoWalletFactory.sol";

interface IKintoAppRegistry {
    /* ============ Structs ============ */

    struct Metadata {
        uint256 tokenId;
        bool dsaEnabled;
        uint256 rateLimitPeriod;
        uint256 rateLimitNumber; // in txs
        uint256 gasLimitPeriod;
        uint256 gasLimitCost; // in eth
        string name;
    }

    /* ============ State Change ============ */

    function registerApp(
        string calldata _name,
        address parentContract,
        address[] calldata appContracts,
        uint256[4] calldata appLimits
    ) external;

    function enableDSA(address app) external;

    function setSponsoredContracts(address _app, address[] calldata _contracts, bool[] calldata _flags) external;

    function updateMetadata(
        string calldata _name,
        address parentContract,
        address[] calldata appContracts,
        uint256[4] calldata appLimits
    ) external;

    /* ============ Basic Viewers ============ */

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function appCount() external view returns (uint256);

    function childToParentContract(address _contract) external view returns (address);

    function getContractLimits(address _contract) external view returns (uint256[4] memory);

    function getAppMetadata(address _contract) external view returns (Metadata memory);

    function getSponsor(address _contract) external view returns (address);

    function isContractSponsored(address _app, address _contract) external view returns (bool);

    function walletFactory() external view returns (IKintoWalletFactory);

    function tokenIdToApp(uint256 _tokenId) external view returns (address);

    /* ============ Constants and attrs ============ */

    function RATE_LIMIT_PERIOD() external view returns (uint256);

    function RATE_LIMIT_THRESHOLD() external view returns (uint256);

    function GAS_LIMIT_PERIOD() external view returns (uint256);

    function GAS_LIMIT_THRESHOLD() external view returns (uint256);
}

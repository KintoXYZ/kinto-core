// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IKintoAppRegistry {
    /* ============ Structs ============ */

    struct Metadata {
        string name;
        address developerWallet; // the address that deploys the wallet
        bool dsaEnabled; // whether or not this application can request PII from users
        uint256 rateLimitPeriod;
        uint256 rateLimitNumber; // in txs
        uint256 gasLimitPeriod;
        uint256 gasLimitCost; // in eth
    }

    /* ============ State Change ============ */

    function registerApp(
        string calldata _name,
        address parentContract,
        address[] calldata childContracts,
        uint256[4] calldata appLimits
    ) external;

    function enableDSA(address app) external;

    function setSponsoredContracts(address _app, address[] calldata _contracts, bool[] calldata _flags) external;

    function updateMetadata(
        string calldata _name,
        address parentContract,
        address[] calldata childContracts,
        uint256[4] calldata appLimits
    ) external;

    /* ============ Basic Viewers ============ */

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function appCount() external view returns (uint256);

    function childToParentContract(address _contract) external view returns (address);

    function getContractLimits(address _contract) external view returns (uint256[4] memory);

    function getAppMetadata(address _contract) external view returns (Metadata memory);

    function getContractSponsor(address _contract) external view returns (address);

    function isContractSponsoredByApp(address _app, address _contract) external view returns (bool);

    /* ============ Constants and attrs ============ */

    function DEVELOPER_ADMIN() external view returns (bytes32);

    function UPGRADER_ROLE() external view returns (bytes32);

    function RATE_LIMIT_PERIOD() external view returns (uint256);

    function RATE_LIMIT_THRESHOLD() external view returns (uint256);

    function GAS_LIMIT_PERIOD() external view returns (uint256);

    function GAS_LIMIT_THRESHOLD() external view returns (uint256);
}

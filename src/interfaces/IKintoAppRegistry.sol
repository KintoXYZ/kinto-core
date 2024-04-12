// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IKintoWalletFactory} from "./IKintoWalletFactory.sol";
import {IKintoID} from "./IKintoID.sol";

interface IKintoAppRegistry {
    /* ============ Errors ============ */

    error KYCRequired(); // KYC Required
    error AlreadyRegistered(); // App already registered
    error ParentAlreadyChild(); // Parent contract is already registered as a child
    error CannotRegisterWallet(); // Wallets can not be registered
    error OnlyAppDeveloper(); // Only app developer can update metadata
    error LengthMismatch();
    error InvalidSponsorSetter(); // "Only developer can set sponsored contracts"
    error DSAAlreadyEnabled(); // DSA already enabled
    error OnlyMintingAllowed(); // Only mint transfers are allowed

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

    function isSponsored(address _app, address _contract) external view returns (bool);

    function walletFactory() external view returns (IKintoWalletFactory);

    function kintoID() external view returns (IKintoID);

    function tokenIdToApp(uint256 _tokenId) external view returns (address);

    /* ============ Constants and attrs ============ */

    function RATE_LIMIT_PERIOD() external view returns (uint256);

    function RATE_LIMIT_THRESHOLD() external view returns (uint256);

    function GAS_LIMIT_PERIOD() external view returns (uint256);

    function GAS_LIMIT_THRESHOLD() external view returns (uint256);
}

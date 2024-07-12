// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IEntryPoint} from "@aa/core/BaseAccount.sol";
import {IKintoWalletFactory} from "./IKintoWalletFactory.sol";
import {IKintoID} from "./IKintoID.sol";
import {IKintoAppRegistry} from "./IKintoAppRegistry.sol";

interface IKintoWallet {
    /* ============ Errors ============ */

    error LengthMismatch();
    error InvalidPolicy(uint8 newPolicy, uint256 newSigners);
    error InvalidInsurancePolicy(uint256 newPolicy);
    error InvalidDevMode(uint256 newDevMode);
    error InvalidInsurancePayment(address token);
    error InvalidSigner();
    error InvalidApp();
    error AppNotWhitelisted(address sponsor, address addr);
    error RecoveryNotStarted();
    error RecoveryTimeNotElapsed();
    error OwnerKYCMustBeBurned();
    error InvalidRecoverer();
    error MaxSignersExceeded(uint256 newSigners);
    error KYCRequired();
    error DuplicateSigner();
    error OnlySelf();
    error OnlyFactory();
    error EmptySigners();

    /* ============ State Change ============ */

    function initialize(address anOwner, address _recoverer) external;

    function execute(address dest, uint256 value, bytes calldata func) external;

    function executeBatch(address[] calldata dest, uint256[] calldata values, bytes[] calldata func) external;

    function setSignerPolicy(uint8 policy) external;

    function resetSigners(address[] calldata newSigners, uint8 policy) external;

    function setFunderWhitelist(address[] calldata newWhitelist, bool[] calldata flags) external;

    function changeRecoverer(address newRecoverer) external;

    function startRecovery() external;

    function completeRecovery(address[] calldata newSigners) external;

    function cancelRecovery() external;

    function setAppKey(address app, address signer) external;

    function whitelistAppAndSetKey(address app, address signer) external;

    function whitelistApp(address[] calldata apps, bool[] calldata flags) external;

    function setInsurancePolicy(uint256 newPolicy, address paymentToken) external;

    /* ============ Basic Viewers ============ */

    function getOwnersCount() external view returns (uint256);

    function getOwners() external view returns (address[] memory);

    function getNonce() external view returns (uint256);

    function getInsurancePrice(uint256 newPolicy, address paymentToken) external view returns (uint256);

    /* ============ Constants and attrs ============ */

    function kintoID() external view returns (IKintoID);

    function insurancePolicy() external view returns (uint256);

    function insuranceTimestamp() external view returns (uint256);

    function inRecovery() external view returns (uint256);

    function owners(uint256 _index) external view returns (address);

    function recoverer() external view returns (address);

    function funderWhitelist(address funder) external view returns (bool);

    function isFunderWhitelisted(address funder) external view returns (bool);

    function appSigner(address app) external view returns (address);

    function appWhitelist(address app) external view returns (bool);

    function appRegistry() external view returns (IKintoAppRegistry);

    function factory() external view returns (IKintoWalletFactory);

    function signerPolicy() external view returns (uint8);

    function MAX_SIGNERS() external view returns (uint8);

    function SINGLE_SIGNER() external view returns (uint8);

    function TWO_SIGNERS() external view returns (uint8);

    function MINUS_ONE_SIGNER() external view returns (uint8);

    function ALL_SIGNERS() external view returns (uint8);

    function RECOVERY_TIME() external view returns (uint256);

    function WALLET_TARGET_LIMIT() external view returns (uint256);
}

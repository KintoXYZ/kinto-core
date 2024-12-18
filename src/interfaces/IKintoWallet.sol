// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IEntryPoint} from "@aa/core/BaseAccount.sol";
import {IKintoWalletFactory} from "./IKintoWalletFactory.sol";
import {IKintoID} from "./IKintoID.sol";
import {IKintoAppRegistry} from "./IKintoAppRegistry.sol";

/**
 * @title IKintoWallet
 * @notice Interface for the KintoWallet smart contract, defining the core functionality of a Kinto wallet
 */
interface IKintoWallet {
    /* ============ Errors ============ */

    /**
     * @notice Thrown when there's a mismatch in array lengths in various operations
     */
    error LengthMismatch();

    /**
     * @notice Thrown when an invalid signer policy is set
     * @param newPolicy The invalid policy attempted to be set
     * @param newSigners The number of signers for which the policy was attempted
     */
    error InvalidPolicy(uint8 newPolicy, uint256 newSigners);

    /**
     * @notice Thrown when an invalid insurance policy is set
     * @param newPolicy The invalid insurance policy attempted to be set
     */
    error InvalidInsurancePolicy(uint256 newPolicy);

    /**
     * @notice Thrown when an invalid dev mode is set
     * @param newDevMode The invalid dev mode attempted to be set
     */
    error InvalidDevMode(uint256 newDevMode);

    /**
     * @notice Thrown when an invalid token is used for insurance payment
     * @param token The invalid token address used
     */
    error InvalidInsurancePayment(address token);

    /**
     * @notice Thrown when an invalid signer is provided
     */
    error InvalidSigner();

    /**
     * @notice Thrown when an invalid app is provided
     */
    error InvalidApp();

    /**
     * @notice Thrown when an app is not whitelisted for a specific operation
     * @param app The app address that is not whitelisted
     * @param addr The address attempting the operation
     */
    error AppNotWhitelisted(address app, address addr);

    /**
     * @notice Thrown when an app is not sponsored for a specific operation
     * @param app The app address that is not sponsored
     * @param addr The address attempting the operation
     */
    error AppNotSponsored(address app, address addr);

    /**
     * @notice Thrown when a recovery process has not been initiated
     */
    error RecoveryNotStarted();

    /**
     * @notice Thrown when the recovery time has not elapsed
     */
    error RecoveryTimeNotElapsed();

    /**
     * @notice Thrown when the owner's KYC status is invalid during recovery
     */
    error OwnerKYCMustBeBurned();

    /**
     * @notice Thrown when an invalid recoverer address is provided
     */
    error InvalidRecoverer();

    /**
     * @notice Thrown when the maximum number of signers is exceeded
     * @param newSigners The number of signers attempted to be set
     */
    error MaxSignersExceeded(uint256 newSigners);

    /**
     * @notice Thrown when a KYC check fails
     */
    error KYCRequired();

    /**
     * @notice Thrown when a duplicate signer is provided
     */
    error DuplicateSigner();

    /**
     * @notice Thrown when a function is called by an unauthorized address
     */
    error OnlySelf();

    /**
     * @notice Thrown when a function is called by an address other than the factory
     */
    error OnlyFactory();

    /**
     * @notice Thrown when an empty list of signers is provided
     */
    error EmptySigners();

    /* ============ State Change Functions ============ */

    /**
     * @notice Initializes the wallet with an owner and recoverer
     * @param anOwner The address of the initial owner
     * @param _recoverer The address of the initial recoverer
     */
    function initialize(address anOwner, address _recoverer) external;

    /**
     * @notice Executes a transaction from the wallet
     * @param dest The destination address for the transaction
     * @param value The amount of ETH to send with the transaction
     * @param func The function data to execute
     */
    function execute(address dest, uint256 value, bytes calldata func) external;

    /**
     * @notice Executes a batch of transactions from the wallet
     * @param dest An array of destination addresses for the transactions
     * @param values An array of ETH amounts to send with each transaction
     * @param func An array of function data to execute for each transaction
     */
    function executeBatch(address[] calldata dest, uint256[] calldata values, bytes[] calldata func) external;

    /**
     * @notice Sets the signer policy for the wallet
     * @param policy The new signer policy to set
     */
    function setSignerPolicy(uint8 policy) external;

    /**
     * @notice Resets the signers for the wallet and optionally changes the policy
     * @param newSigners An array of new signer addresses
     * @param policy The new signer policy to set
     */
    function resetSigners(address[] calldata newSigners, uint8 policy) external;

    /**
     * @notice Sets the whitelist for addresses allowed to fund the wallet
     * @param newWhitelist An array of addresses to whitelist
     * @param flags An array of boolean flags indicating whether each address should be whitelisted
     */
    function setFunderWhitelist(address[] calldata newWhitelist, bool[] calldata flags) external;

    /**
     * @notice Gets the address of the AccessPoint contract associated with this wallet
     * @return The address of the AccessPoint contract
     */
    function getAccessPoint() external view returns (address);

    /**
     * @notice Changes the recoverer address for the wallet
     * @param newRecoverer The address of the new recoverer
     */
    function changeRecoverer(address newRecoverer) external;

    /**
     * @notice Initiates the recovery process for the wallet
     */
    function startRecovery() external;

    /**
     * @notice Completes the recovery process, setting new signers
     * @param newSigners An array of new signer addresses to set after recovery
     */
    function completeRecovery(address[] calldata newSigners) external;

    /**
     * @notice Cancels an ongoing recovery process
     */
    function cancelRecovery() external;

    /**
     * @notice Sets an app-specific key for the wallet
     * @param app The address of the app
     * @param signer The address of the app-specific signer
     */
    function setAppKey(address app, address signer) external;

    /**
     * @notice Whitelists an app and sets its app-specific key in one operation
     * @param app The address of the app to whitelist
     * @param signer The address of the app-specific signer
     */
    function whitelistAppAndSetKey(address app, address signer) external;

    /**
     * @notice Whitelists or de-whitelists multiple apps
     * @param apps An array of app addresses
     * @param flags An array of boolean flags indicating whether each app should be whitelisted
     */
    function whitelistApp(address[] calldata apps, bool[] calldata flags) external;

    /**
     * @notice Sets the insurance policy for the wallet
     * @param newPolicy The new insurance policy to set
     * @param paymentToken The token to use for the insurance payment
     */
    function setInsurancePolicy(uint256 newPolicy, address paymentToken) external;

    /* ============ View Functions ============ */

    /**
     * @notice Gets the number of owners (signers) for the wallet
     * @return The number of owners
     */
    function getOwnersCount() external view returns (uint256);

    /**
     * @notice Gets the list of owners (signers) for the wallet
     * @return An array of owner addresses
     */
    function getOwners() external view returns (address[] memory);

    /**
     * @notice Gets the current nonce of the wallet
     * @return The current nonce
     */
    function getNonce() external view returns (uint256);

    /**
     * @notice Calculates the price of an insurance policy
     * @param newPolicy The policy level to price
     * @param paymentToken The token in which the price is denominated
     * @return The price of the insurance policy
     */
    function getInsurancePrice(uint256 newPolicy, address paymentToken) external view returns (uint256);

    /* ============ Getter Functions ============ */

    /**
     * @notice The KintoID contract used for KYC verification
     */
    function kintoID() external view returns (IKintoID);

    /**
     * @notice The current insurance policy of the wallet
     */
    function insurancePolicy() external view returns (uint256);

    /**
     * @notice The timestamp when the current insurance policy was set
     */
    function insuranceTimestamp() external view returns (uint256);

    /**
     * @notice The timestamp when recovery was initiated, or 0 if not in recovery
     */
    function inRecovery() external view returns (uint256);

    /**
     * @notice Gets the owner at a specific index
     * @param _index The index of the owner to retrieve
     * @return The address of the owner at the given index
     */
    function owners(uint256 _index) external view returns (address);

    /**
     * @notice The address of the current recoverer
     */
    function recoverer() external view returns (address);

    /**
     * @notice Checks if an address is whitelisted to fund the wallet
     * @param funder The address to check
     * @return Whether the address is whitelisted
     */
    function funderWhitelist(address funder) external view returns (bool);

    /**
     * @notice Checks if an address is whitelisted to fund the wallet, including owners and bridge contracts
     * @param funder The address to check
     * @return Whether the address is whitelisted
     */
    function isFunderWhitelisted(address funder) external view returns (bool);

    /**
     * @notice Gets the app-specific signer for a given app
     * @param app The address of the app
     * @return The address of the app-specific signer
     */
    function appSigner(address app) external view returns (address);

    /**
     * @notice Checks if an app is whitelisted by user
     * @param app The address of the app to check
     * @return Whether the app is whitelisted
     */
    function appWhitelist(address app) external view returns (bool);

    /**
     * @notice Checks if an app is whitelisted by user or a system app
     * @param app The address of the app to check
     * @return Whether the app is approved
     */
    function isAppApproved(address app) external view returns (bool);

    /**
     * @notice The KintoAppRegistry contract used by this wallet
     */
    function appRegistry() external view returns (IKintoAppRegistry);

    /**
     * @notice The KintoWalletFactory contract that created this wallet
     */
    function factory() external view returns (IKintoWalletFactory);

    /**
     * @notice The current signer policy of the wallet
     */
    function signerPolicy() external view returns (uint8);

    /**
     * @notice The maximum number of signers allowed for the wallet
     */
    function MAX_SIGNERS() external view returns (uint8);

    /**
     * @notice The policy constant for a single signer requirement
     */
    function SINGLE_SIGNER() external view returns (uint8);

    /**
     * @notice The policy constant for a two signers requirement
     */
    function TWO_SIGNERS() external view returns (uint8);

    /**
     * @notice The policy constant for an n-1 signers requirement
     */
    function MINUS_ONE_SIGNER() external view returns (uint8);

    /**
     * @notice The policy constant for an all signers requirement
     */
    function ALL_SIGNERS() external view returns (uint8);

    /**
     * @notice The duration of the recovery process
     */
    function RECOVERY_TIME() external view returns (uint256);

    /**
     * @notice The maximum number of wallet-targeted operations allowed in a batch
     */
    function WALLET_TARGET_LIMIT() external view returns (uint256);
}

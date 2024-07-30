// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IKintoWalletFactory} from "./IKintoWalletFactory.sol";
import {IKintoID} from "./IKintoID.sol";

/**
 * @title IKintoAppRegistry
 * @notice Interface for the KintoAppRegistry contract
 */
interface IKintoAppRegistry {
    /* ============ Errors ============ */

    /// @notice Thrown when KYC is required but not completed
    error KYCRequired();

    /// @notice Thrown when attempting to register an already registered app
    /// @param app The address of the app that is already registered
    error AlreadyRegistered(address app);

    /// @notice Thrown when a parent contract is already registered as a child
    /// @param parent The address of the parent contract
    error ParentAlreadyChild(address parent);

    /// @notice Thrown when a child contract is already registered
    /// @param child The address of the child contract
    error ChildAlreadyRegistered(address child);

    /// @notice Thrown when attempting to register a reserved contract as an app contract
    /// @param target The address of the reserved contract
    error ReservedContract(address target);

    /// @notice Thrown when attempting to register a wallet as an app
    /// @param wallet The address of the wallet
    error CannotRegisterWallet(address wallet);

    /// @notice Thrown when a non-developer attempts to update app metadata
    /// @param caller The address of the caller
    /// @param owner The address of the app owner
    error OnlyAppDeveloper(address caller, address owner);

    /// @notice Thrown when there's a mismatch in array lengths
    /// @param contractsLength The length of the contracts array
    /// @param flagsLength The length of the flags array
    error LengthMismatch(uint256 contractsLength, uint256 flagsLength);

    /// @notice Thrown when an invalid address attempts to set sponsored contracts
    /// @param caller The address of the caller
    /// @param owner The address of the app owner
    error InvalidSponsorSetter(address caller, address owner);

    /// @notice Thrown when attempting to enable DSA for an app that already has it enabled
    /// @param app The address of the app
    error DSAAlreadyEnabled(address app);

    /// @notice Thrown when attempting a disallowed transfer operation
    error OnlyMintingAllowed();

    /// @notice Thrown when an invalid wallet address is provided
    /// @param wallet The address of the invalid wallet
    error InvalidWallet(address wallet);

    /// @notice Thrown when a contract address is provided instead of an EOA for a developer
    /// @param eoa The address that should be an EOA but is a contract
    error DevEoaIsContract(address eoa);

    /// @notice Thrown when a contract address has no bytecode
    /// @param target The address of the contract without bytecode
    error ContractHasNoBytecode(address target);

    /* ============ Events ============ */

    /// @notice Emitted when a new app is registered
    /// @param app The address of the registered app
    /// @param owner The address of the app owner
    /// @param timestamp The timestamp of the registration
    event AppRegistered(address indexed app, address owner, uint256 timestamp);

    /// @notice Emitted when an app's metadata is updated
    /// @param app The address of the updated app
    /// @param owner The address of the app owner
    /// @param timestamp The timestamp of the update
    event AppUpdated(address indexed app, address owner, uint256 timestamp);

    /// @notice Emitted when DSA is enabled for an app
    /// @param app The address of the app
    /// @param timestamp The timestamp when DSA was enabled
    event AppDSAEnabled(address indexed app, uint256 timestamp);

    /// @notice Emitted when the system contracts are updated
    /// @param oldSystemContracts The array of old system contract addresses
    /// @param newSystemContracts The array of new system contract addresses
    event SystemContractsUpdated(address[] oldSystemContracts, address[] newSystemContracts);

    /// @notice Emitted when the reserved contracts are updated
    /// @param oldReservedContracts The array of old reserved contract addresses
    /// @param newReservedContracts The array of new reserved contract addresses
    event ReservedContractsUpdated(address[] oldReservedContracts, address[] newReservedContracts);

    /// @notice Emitted when a new deployer is set
    /// @param newDeployer The address of the new deployer
    event DeployerSet(address indexed newDeployer);

    /* ============ Structs ============ */

    /**
     * @notice Struct to hold metadata for an app
     * @param tokenId The token ID associated with the app
     * @param dsaEnabled Whether Data Sharing Agreement is enabled for the app
     * @param rateLimitPeriod The period for rate limiting
     * @param rateLimitNumber The number of transactions allowed in the rate limit period
     * @param gasLimitPeriod The period for gas limiting
     * @param gasLimitCost The gas cost limit for the period
     * @param name The name of the app
     * @param devEOAs Array of developer EOA addresses
     * @param appContracts Array of app contract addresses
     */
    struct Metadata {
        uint256 tokenId;
        bool dsaEnabled;
        uint256 rateLimitPeriod;
        uint256 rateLimitNumber;
        uint256 gasLimitPeriod;
        uint256 gasLimitCost;
        string name;
        address[] devEOAs;
        address[] appContracts;
    }

    /* ============ State Change Functions ============ */

    /**
     * @notice Registers a new app
     * @param _name The name of the app
     * @param parentContract The address of the parent contract
     * @param appContracts An array of app contract addresses
     * @param appLimits An array of app limits [rateLimitPeriod, rateLimitNumber, gasLimitPeriod, gasLimitCost]
     * @param devEOAs An array of developer EOA addresses
     */
    function registerApp(
        string calldata _name,
        address parentContract,
        address[] calldata appContracts,
        uint256[4] calldata appLimits,
        address[] calldata devEOAs
    ) external;

    /**
     * @notice Enables Data Sharing Agreement for an app
     * @param app The address of the app
     */
    function enableDSA(address app) external;

    /**
     * @notice Sets sponsored contracts for an app
     * @param app The address of the app
     * @param targets An array of contract addresses to be sponsored
     * @param flags An array of boolean flags indicating whether each contract is sponsored
     */
    function setSponsoredContracts(address app, address[] calldata targets, bool[] calldata flags) external;

    /**
     * @notice Updates the metadata of an app
     * @param _name The new name of the app
     * @param parentContract The address of the parent contract
     * @param appContracts An array of new app contract addresses
     * @param appLimits An array of new app limits [rateLimitPeriod, rateLimitNumber, gasLimitPeriod, gasLimitCost]
     * @param devEOAs An array of new developer EOA addresses
     */
    function updateMetadata(
        string calldata _name,
        address parentContract,
        address[] calldata appContracts,
        uint256[4] calldata appLimits,
        address[] calldata devEOAs
    ) external;

    /**
     * @notice Overrides the parent contract of a child contract
     * @param child The address of the child contract
     * @param parent The address of the new parent contract
     */
    function overrideChildToParentContract(address child, address parent) external;

    /**
     * @notice Updates the system contracts
     * @param newSystemContracts An array of new system contract addresses
     */
    function updateSystemContracts(address[] calldata newSystemContracts) external;

    /**
     * @notice Updates the reserved contracts
     * @param newReservedContracts An array of new reserved contract addresses
     */
    function updateReservedContracts(address[] calldata newReservedContracts) external;

    /**
     * @notice Sets the deployer EOA for a wallet
     * @param wallet The address of the wallet
     * @param deployer The address of the deployer EOA
     */
    function setDeployerEOA(address wallet, address deployer) external;

    /* ============ View Functions ============ */

    /**
     * @notice Returns the name of the token
     * @return The name of the token
     */
    function name() external pure returns (string memory);

    /**
     * @notice Returns the symbol of the token
     * @return The symbol of the token
     */
    function symbol() external pure returns (string memory);

    /**
     * @notice Returns the total number of registered apps
     * @return The count of registered apps
     */
    function appCount() external view returns (uint256);

    /**
     * @notice Returns the parent contract of a child contract
     * @param _contract The address of the child contract
     * @return The address of the parent contract
     */
    function childToParentContract(address _contract) external view returns (address);

    /**
     * @notice Returns the limits for a contract
     * @param target The address of the contract
     * @return An array of limits [rateLimitPeriod, rateLimitNumber, gasLimitPeriod, gasLimitCost]
     */
    function getContractLimits(address target) external view returns (uint256[4] memory);

    /**
     * @notice Returns the metadata for an app
     * @param target The address of the app contract
     * @return The metadata struct for the app
     */
    function getAppMetadata(address target) external view returns (Metadata memory);

    /**
     * @notice Returns the sponsor of a contract
     * @param target The address of the contract
     * @return The address of the sponsor
     */
    function getSponsor(address target) external view returns (address);

    /**
     * @notice Checks if a contract is sponsored by an app
     * @param app The address of the app
     * @param target The address of the contract
     * @return A boolean indicating whether the contract is sponsored
     */
    function isSponsored(address app, address target) external view returns (bool);

    /**
     * @notice Returns the wallet factory contract
     * @return The address of the wallet factory contract
     */
    function walletFactory() external view returns (IKintoWalletFactory);

    /**
     * @notice Returns the KintoID contract
     * @return The address of the KintoID contract
     */
    function kintoID() external view returns (IKintoID);

    /**
     * @notice Returns the app address for a given token ID
     * @param _tokenId The token ID
     * @return The address of the app
     */
    function tokenIdToApp(uint256 _tokenId) external view returns (address);

    /**
     * @notice Returns the app address for a given developer EOA
     * @param _eoa The address of the developer EOA
     * @return The address of the app
     */
    function devEoaToApp(address _eoa) external view returns (address);

    /**
     * @notice Returns an array of all system contract addresses
     * @return An array of system contract addresses
     */
    function getSystemContracts() external view returns (address[] memory);

    /**
     * @notice Returns the system contract address at a given index
     * @param index The index in the system contracts array
     * @return The address of the system contract
     */
    function systemContracts(uint256 index) external view returns (address);

    /**
     * @notice Checks if an address is a system contract
     * @param addr The address to check
     * @return A boolean indicating whether the address is a system contract
     */
    function isSystemContract(address addr) external view returns (bool);

    /**
     * @notice Returns an array of all reserved contract addresses
     * @return An array of reserved contract addresses
     */
    function getReservedContracts() external view returns (address[] memory);

    /**
     * @notice Returns the reserved contract address at a given index
     * @param index The index in the reserved contracts array
     * @return The address of the reserved contract
     */
    function reservedContracts(uint256 index) external view returns (address);

    /**
     * @notice Checks if an address is a reserved contract
     * @param addr The address to check
     * @return A boolean indicating whether the address is a reserved contract
     */
    function isReservedContract(address addr) external view returns (bool);

    /**
     * @notice Returns the wallet address for a given deployer
     * @param addr The address of the deployer
     * @return The address of the associated wallet
     */
    function deployerToWallet(address addr) external view returns (address);

    /**
     * @notice Returns the deployer address for a given wallet
     * @param addr The address of the wallet
     * @return The address of the associated deployer
     */
    function walletToDeployer(address addr) external view returns (address);

    /**
     * @notice Determines if a contract call is allowed from a `to` address to `to` address
     * @param from The address initiating the call
     * @param to The address being called
     * @return A boolean indicating whether the call is allowed (true) or not (false)
     */
    function isContractCallAllowedFromEOA(address from, address to) external view returns (bool);

    /* ============ Constants and Attributes ============ */

    /**
     * @notice Returns the rate limit period
     * @return The rate limit period in seconds
     */
    function RATE_LIMIT_PERIOD() external view returns (uint256);

    /**
     * @notice Returns the rate limit threshold
     * @return The rate limit threshold
     */
    function RATE_LIMIT_THRESHOLD() external view returns (uint256);

    /**
     * @notice Returns the gas limit period
     * @return The gas limit period in seconds
     */
    function GAS_LIMIT_PERIOD() external view returns (uint256);

    /**
     * @notice Returns the gas limit threshold
     * @return The gas limit threshold in wei
     */
    function GAS_LIMIT_THRESHOLD() external view returns (uint256);
}

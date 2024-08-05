// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../interfaces/IKintoWalletFactory.sol";
import "../interfaces/IKintoID.sol";
import "../interfaces/IFaucet.sol";
import "../interfaces/IEngenCredits.sol";
import "../interfaces/IKintoAppRegistry.sol";

/**
 * @title IKYCViewer Interface
 * @notice Interface for a contract that provides KYC (Know Your Customer) related information
 * @dev This interface defines functions to check KYC status, sanctions safety, and retrieve user information
 */
interface IKYCViewer {
    /**
     * @notice Struct to hold various user information
     * @dev This struct contains balance, policy, KYC status, and other relevant user data
     */
    struct UserInfo {
        /// @notice The ETH balance of the user's EOA (Externally Owned Account)
        uint256 ownerBalance;
        /// @notice The ETH balance of the user's Kinto wallet
        uint256 walletBalance;
        /// @notice The policy governing the wallet's signers (e.g., number of required signatures)
        uint256 walletPolicy;
        /// @notice Array of addresses that own the wallet
        address[] walletOwners;
        /// @notice Amount of ETH claimed from the faucet
        bool claimedFaucet;
        /// @notice Indicates whether the user has a Kinto ID NFT
        bool hasNFT;
        /// @notice Total Engen Credits earned by the user
        uint256 engenCreditsEarned;
        /// @notice Amount of Engen Credits claimed by the user
        uint256 engenCreditsClaimed;
        /// @notice Indicates whether the user has completed KYC
        bool isKYC;
        /// @notice Timestamp of when the wallet entered recovery mode (0 if not in recovery)
        uint256 recoveryTs;
        /// @notice The insurance policy of the wallet (details depend on implementation)
        uint256 insurancePolicy;
        /// @notice Indicates whether the wallet has a valid insurance policy
        bool hasValidInsurance;
        /// @notice Timestamp of when the insurance policy was last updated
        uint256 insuranceTimestamp;
        /// @notice Address of the EOA that deployed the wallet (if applicable)
        address deployer;
    }

    /**
     * @notice Returns the KintoWalletFactory contract address
     * @return The address of the KintoWalletFactory contract
     */
    function walletFactory() external view returns (IKintoWalletFactory);

    /**
     * @notice Returns the KintoID contract address
     * @return The address of the KintoID contract
     */
    function kintoID() external view returns (IKintoID);

    /**
     * @notice Returns the Faucet contract address
     * @return The address of the Faucet contract
     */
    function faucet() external view returns (IFaucet);

    /**
     * @notice Returns the EngenCredits contract address
     * @return The address of the EngenCredits contract
     */
    function engenCredits() external view returns (IEngenCredits);

    /**
     * @notice Returns the KintoAppRegistry contract address
     * @return The address of the KintoAppRegistry contract
     */
    function kintoAppRegistry() external view returns (IKintoAppRegistry);

    /**
     * @notice Checks if an address is KYC'd
     * @param addr The address to check
     * @return True if the address is KYC'd, false otherwise
     */
    function isKYC(address addr) external view returns (bool);

    /**
     * @notice Checks if an account is sanctions safe
     * @param account The account to check
     * @return True if the account is sanctions safe, false otherwise
     */
    function isSanctionsSafe(address account) external view returns (bool);

    /**
     * @notice Checks if an account is sanctions safe in a specific country
     * @param account The account to check
     * @param _countryId The ID of the country to check against
     * @return True if the account is sanctions safe in the specified country, false otherwise
     */
    function isSanctionsSafeIn(address account, uint16 _countryId) external view returns (bool);

    /**
     * @notice Checks if an account is registered as a company
     * @param account The account to check
     * @return True if the account is registered as a company, false otherwise
     */
    function isCompany(address account) external view returns (bool);

    /**
     * @notice Checks if an account is registered as an individual
     * @param account The account to check
     * @return True if the account is registered as an individual, false otherwise
     */
    function isIndividual(address account) external view returns (bool);

    /**
     * @notice Gets the wallet owners for a given wallet address
     * @param wallet The wallet address to check
     * @return An array of addresses representing the wallet owners
     */
    function getWalletOwners(address wallet) external view returns (address[] memory);

    /**
     * @notice Gets detailed user information for a given account and wallet
     * @param account The account address to check
     * @param wallet The wallet address to check
     * @return A UserInfo struct containing detailed information about the user
     */
    function getUserInfo(address account, address payable wallet) external view returns (UserInfo memory);

    /**
     * @notice Gets the developer apps associated with a wallet
     * @param wallet The wallet address to check
     * @return An array of IKintoAppRegistry.Metadata structs representing the developer's apps
     */
    function getDevApps(address wallet) external view returns (IKintoAppRegistry.Metadata[] memory);

    /**
     * @notice Checks if an account has multiple traits
     * @param account The account to check
     * @param _traitIds An array of trait IDs to check for
     * @return An array of booleans indicating whether the account has each trait
     */
    function hasTraits(address account, uint16[] memory _traitIds) external view returns (bool[] memory);

    /**
     * @notice Checks if an account has a specific trait
     * @param account The account to check
     * @param _traitId The ID of the trait to check for
     * @return bool True if the account has the specified trait, false otherwise
     */
    function hasTrait(address account, uint16 _traitId) external view returns (bool);

    /**
     * @notice Gets the country code for an account
     * @param account The account to check
     * @return uint16 The country code of the account, or 0 if not found
     */
    function getCountry(address account) external view returns (uint16);

    /**
     * @notice Retrieves the ERC20 token balances for a specific target address
     * @dev This view function allows fetching balances for multiple tokens in a single call,
     *      which can save considerable gas over multiple calls
     * @param tokens An array of token addresses to query balances for
     * @param target The address whose balances will be queried
     * @return balances An array of balances corresponding to the array of tokens provided
     */
    function getBalances(address[] memory tokens, address target) external view returns (uint256[] memory balances);
}

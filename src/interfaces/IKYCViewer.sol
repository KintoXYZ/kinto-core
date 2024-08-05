// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../interfaces/IKintoWalletFactory.sol";
import "../interfaces/IKintoID.sol";
import "../interfaces/IFaucet.sol";
import "../interfaces/IEngenCredits.sol";
import "../interfaces/IKintoAppRegistry.sol";

/// @title IKYCViewer Interface
/// @notice Interface for a contract that provides KYC (Know Your Customer) related information
/// @dev This interface defines functions to check KYC status, sanctions safety, and retrieve user information
interface IKYCViewer {

    /// @notice Struct to hold various user information
    /// @dev This struct contains balance, policy, KYC status, and other relevant user data
    struct UserInfo {
        uint256 ownerBalance;
        uint256 walletBalance;
        uint256 walletPolicy;
        address[] walletOwners;
        bool claimedFaucet;
        bool hasNFT;
        uint256 engenCreditsEarned;
        uint256 engenCreditsClaimed;
        bool isKYC;
        uint256 recoveryTs;
        uint256 insurancePolicy;
        bool hasValidInsurance;
        uint256 insuranceTimestamp;
        address deployer;
    }

    /// @notice Returns the KintoWalletFactory contract address
    /// @return The address of the KintoWalletFactory contract
    function walletFactory() external view returns (IKintoWalletFactory);

    /// @notice Returns the KintoID contract address
    /// @return The address of the KintoID contract
    function kintoID() external view returns (IKintoID);

    /// @notice Returns the Faucet contract address
    /// @return The address of the Faucet contract
    function faucet() external view returns (IFaucet);

    /// @notice Returns the EngenCredits contract address
    /// @return The address of the EngenCredits contract
    function engenCredits() external view returns (IEngenCredits);

    /// @notice Returns the KintoAppRegistry contract address
    /// @return The address of the KintoAppRegistry contract
    function kintoAppRegistry() external view returns (IKintoAppRegistry);

    /// @notice Checks if an address is KYC'd
    /// @param addr The address to check
    /// @return True if the address is KYC'd, false otherwise
    function isKYC(address addr) external view returns (bool);

    /// @notice Checks if an account is sanctions safe
    /// @param account The account to check
    /// @return True if the account is sanctions safe, false otherwise
    function isSanctionsSafe(address account) external view returns (bool);

    /// @notice Checks if an account is sanctions safe in a specific country
    /// @param account The account to check
    /// @param _countryId The ID of the country to check against
    /// @return True if the account is sanctions safe in the specified country, false otherwise
    function isSanctionsSafeIn(address account, uint16 _countryId) external view returns (bool);

    /// @notice Checks if an account is registered as a company
    /// @param account The account to check
    /// @return True if the account is registered as a company, false otherwise
    function isCompany(address account) external view returns (bool);

    /// @notice Checks if an account is registered as an individual
    /// @param account The account to check
    /// @return True if the account is registered as an individual, false otherwise
    function isIndividual(address account) external view returns (bool);

    /// @notice Gets the wallet owners for a given wallet address
    /// @param wallet The wallet address to check
    /// @return An array of addresses representing the wallet owners
    function getWalletOwners(address wallet) external view returns (address[] memory);

    /// @notice Gets detailed user information for a given account and wallet
    /// @param account The account address to check
    /// @param wallet The wallet address to check
    /// @return A UserInfo struct containing detailed information about the user
    function getUserInfo(address account, address payable wallet) external view returns (UserInfo memory);

    /// @notice Gets the developer apps associated with a wallet
    /// @param wallet The wallet address to check
    /// @return An array of IKintoAppRegistry.Metadata structs representing the developer's apps
    function getDevApps(address wallet) external view returns (IKintoAppRegistry.Metadata[] memory);
}

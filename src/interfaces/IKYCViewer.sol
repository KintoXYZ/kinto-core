// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IKintoID.sol";
import "./IKintoWalletFactory.sol";
import "./IFaucet.sol";
import "./IEngenCredits.sol";
import "./IKintoAppRegistry.sol";

interface IKYCViewer {
    /* ============ Errors ============ */
    error OnlyOwner();

    /* ============ Structs ============ */

    struct UserInfo {
        uint256 insurancePolicy;
        uint256 ownerBalance;
        uint256 walletBalance;
        uint256 walletPolicy;
        uint256 recoveryTs;
        uint256 engenCreditsEarned;
        uint256 engenCreditsClaimed;
        uint256 insuranceTimestamp;
        address[] walletOwners;
        bool claimedFaucet;
        bool hasNFT;
        bool isKYC;
        bool hasValidInsurance;
        address deployer;
    }

    /* ============ Basic Viewers ============ */

    function isKYC(address _address) external view returns (bool);

    function isSanctionsSafe(address _account) external view returns (bool);

    function isSanctionsSafeIn(address _account, uint16 _countryId) external view returns (bool);

    function isCompany(address _account) external view returns (bool);

    function isIndividual(address _account) external view returns (bool);

    function hasTrait(address _account, uint8 _traitId) external view returns (bool);

    function getWalletOwners(address _wallet) external view returns (address[] memory);

    function getUserInfo(address _account, address payable _wallet) external view returns (UserInfo memory);

    function getBalances(address[] memory tokens, address target) external view returns (uint256[] memory balances);

    function getDevApps(address _wallet) external view returns (IKintoAppRegistry.Metadata[] memory);

    /* ============ Constants and attrs ============ */

    function kintoID() external view returns (IKintoID);

    function walletFactory() external view returns (IKintoWalletFactory);

    function faucet() external view returns (IFaucet);

    function engenCredits() external view returns (IEngenCredits);

    function kintoAppRegistry() external view returns (IKintoAppRegistry);
}

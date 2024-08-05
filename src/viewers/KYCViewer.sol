// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC721Enumerable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

import "../interfaces/IKintoID.sol";
import "../interfaces/IKintoWalletFactory.sol";
import "../interfaces/IKYCViewer.sol";
import "../interfaces/IFaucet.sol";
import "../interfaces/IEngenCredits.sol";
import "../interfaces/IKintoAppRegistry.sol";

import "./CountryCodes.sol";

/**
 * @title KYCViewer
 * @notice A contract that provides KYC (Know Your Customer) related information and utilities
 * @dev This contract implements the IKYCViewer interface and is upgradeable
 */
contract KYCViewer is Initializable, UUPSUpgradeable, OwnableUpgradeable, IKYCViewer {
    /* ============ Constants ============ */

    /// @inheritdoc IKYCViewer
    IKintoWalletFactory public immutable override walletFactory;

    /// @inheritdoc IKYCViewer
    IKintoID public immutable override kintoID;

    /// @inheritdoc IKYCViewer
    IFaucet public immutable override faucet;

    /// @inheritdoc IKYCViewer
    IEngenCredits public immutable override engenCredits;

    /// @inheritdoc IKYCViewer
    IKintoAppRegistry public immutable override kintoAppRegistry;

    /* ============ State Variables ============ */

    /* ============ Constructor & Upgrades ============ */

    /**
     * @notice Contract constructor
     * @dev Sets up immutable state variables and disables initializers
     * @param _kintoWalletFactory Address of the KintoWalletFactory contract
     * @param _faucet Address of the Faucet contract
     * @param _engenCredits Address of the EngenCredits contract
     * @param _kintoAppRegistry Address of the KintoAppRegistry contract
     */
    constructor(address _kintoWalletFactory, address _faucet, address _engenCredits, address _kintoAppRegistry) {
        _disableInitializers();
        walletFactory = IKintoWalletFactory(_kintoWalletFactory);
        kintoID = walletFactory.kintoID();
        faucet = IFaucet(_faucet);
        engenCredits = IEngenCredits(_engenCredits);
        kintoAppRegistry = IKintoAppRegistry(_kintoAppRegistry);
    }

    /**
     * @notice Initializes the contract
     * @dev Sets up the owner and UUPS upgradeability
     */
    function initialize() external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        _transferOwnership(msg.sender);
    }

    /**
     * @notice Authorizes an upgrade to a new implementation
     * @dev Can only be called by the contract owner
     * @param newImplementation Address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {}

    /* ============ Basic Viewers ============ */

    /// @inheritdoc IKYCViewer
    function isKYC(address addr) external view override returns (bool) {
        return kintoID.isKYC(_getOwnerOrWallet(addr));
    }

    /// @inheritdoc IKYCViewer
    function isSanctionsSafe(address account) external view override returns (bool) {
        return kintoID.isSanctionsSafe(_getOwnerOrWallet(account));
    }

    /// @inheritdoc IKYCViewer
    function isSanctionsSafeIn(address account, uint16 _countryId) external view override returns (bool) {
        return kintoID.isSanctionsSafeIn(_getOwnerOrWallet(account), _countryId);
    }

    /// @inheritdoc IKYCViewer
    function isCompany(address account) external view override returns (bool) {
        return kintoID.isCompany(_getOwnerOrWallet(account));
    }

    /// @inheritdoc IKYCViewer
    function isIndividual(address account) external view override returns (bool) {
        return kintoID.isIndividual(_getOwnerOrWallet(account));
    }

    /// @inheritdoc IKYCViewer
    function hasTrait(address account, uint16 _traitId) external view returns (bool) {
        return kintoID.hasTrait(_getOwnerOrWallet(account), _traitId);
    }

    /// @inheritdoc IKYCViewer
    function hasTraits(address account, uint16[] memory _traitIds) public view returns (bool[] memory) {
        address finalAddress = _getOwnerOrWallet(account);
        bool[] memory results = new bool[](_traitIds.length);
        for (uint256 i = 0; i < _traitIds.length; i++) {
            results[i] = kintoID.hasTrait(finalAddress, _traitIds[i]);
        }
        return results;
    }

    /// @inheritdoc IKYCViewer
    function getCountry(address account) external view returns (uint16) {
        uint16[] memory validCodes = CountryCodes.getValidCountryCodes();
        address finalAddress = _getOwnerOrWallet(account);

        for (uint16 i = 0; i < validCodes.length; i++) {
            bool hasTraitValue = kintoID.hasTrait(finalAddress, uint16(validCodes[i]));
            if (hasTraitValue) {
                return validCodes[i];
            }
        }

        return 0; // Return 0 if no country trait is found
    }

    /// @inheritdoc IKYCViewer
    function getWalletOwners(address wallet) public view override returns (address[] memory owners) {
        // return owners if wallet exists and has a valid timestamp
        if (wallet != address(0) && walletFactory.getWalletTimestamp(wallet) > 0) {
            uint256 ownersCount = IKintoWallet(payable(wallet)).getOwnersCount();
            owners = new address[](ownersCount);
            for (uint256 i = 0; i < ownersCount; i++) {
                owners[i] = IKintoWallet(payable(wallet)).owners(i);
            }
        }
    }

    /// @inheritdoc IKYCViewer
    function getUserInfo(address account, address payable wallet)
        external
        view
        override
        returns (IKYCViewer.UserInfo memory info)
    {
        bool hasWallet = wallet != address(0) && walletFactory.getWalletTimestamp(wallet) > 0;
        info = IKYCViewer.UserInfo({
            ownerBalance: account.balance,
            walletBalance: hasWallet ? wallet.balance : 0,
            walletPolicy: hasWallet ? IKintoWallet(wallet).signerPolicy() : 0,
            walletOwners: hasWallet ? getWalletOwners(wallet) : new address[](0),
            claimedFaucet: faucet.claimed(account),
            hasNFT: IERC721(address(kintoID)).balanceOf(account) > 0,
            engenCreditsEarned: engenCredits.earnedCredits(wallet),
            engenCreditsClaimed: IERC20(address(engenCredits)).balanceOf(wallet),
            isKYC: kintoID.isKYC(account),
            recoveryTs: hasWallet ? IKintoWallet(wallet).inRecovery() : 0,
            insurancePolicy: hasWallet ? IKintoWallet(wallet).insurancePolicy() : 0,
            hasValidInsurance: hasWallet ? (IKintoWallet(wallet).insuranceTimestamp() + 365 days) >= block.timestamp : false,
            insuranceTimestamp: hasWallet ? IKintoWallet(wallet).insuranceTimestamp() : 0,
            deployer: hasWallet ? kintoAppRegistry.walletToDeployer(wallet) : address(0)
        });
    }

    /// @inheritdoc IKYCViewer
    function getDevApps(address wallet) external view override returns (IKintoAppRegistry.Metadata[] memory) {
        uint256 balance = IERC721Enumerable(address(kintoAppRegistry)).balanceOf(wallet);
        IKintoAppRegistry.Metadata[] memory apps = new IKintoAppRegistry.Metadata[](balance);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = IERC721Enumerable(address(kintoAppRegistry)).tokenOfOwnerByIndex(wallet, i);
            apps[i] = kintoAppRegistry.getAppMetadata(kintoAppRegistry.tokenIdToApp(tokenId));
        }
        return apps;
    }

    /// @inheritdoc IKYCViewer
    function getBalances(address[] memory tokens, address target) external view returns (uint256[] memory balances) {
        balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0) || tokens[i] == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
                balances[i] = target.balance;
            } else {
                balances[i] = IERC20(tokens[i]).balanceOf(target);
            }
        }
    }

    /* ============ Helpers ============ */

    /**
     * @notice Helper function to get the owner address or wallet address
     * @dev If the input address is a wallet, it returns the first owner's address
     * @param addr The address to check
     * @return The owner's address or the input address if it's not a wallet
     */
    function _getOwnerOrWallet(address addr) private view returns (address) {
        if (walletFactory.getWalletTimestamp(addr) > 0) {
            return IKintoWallet(payable(addr)).owners(0);
        }
        return addr;
    }
}

contract KYCViewerV14 is KYCViewer {
    constructor(address _kintoWalletFactory, address _faucet, address _engenCredits, address _kintoAppRegistry)
        KYCViewer(_kintoWalletFactory, _faucet, _engenCredits, _kintoAppRegistry)
    {}
}

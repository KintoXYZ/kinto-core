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
 * @dev A viewer class that helps developers to check if an address is KYC'd
 *      Abstracts complexity by checking both wallet and EOA.
 */
contract KYCViewer is Initializable, UUPSUpgradeable, OwnableUpgradeable, IKYCViewer {
    /* ============ State Variables ============ */

    IKintoWalletFactory public immutable override walletFactory;
    IKintoID public immutable override kintoID;
    IFaucet public immutable override faucet;
    IEngenCredits public immutable override engenCredits;
    IKintoAppRegistry public immutable override kintoAppRegistry;

    /* ============ Constructor & Upgrades ============ */
    constructor(address _kintoWalletFactory, address _faucet, address _engenCredits, address _kintoAppRegistry) {
        _disableInitializers();
        walletFactory = IKintoWalletFactory(_kintoWalletFactory);
        kintoID = walletFactory.kintoID();
        faucet = IFaucet(_faucet);
        engenCredits = IEngenCredits(_engenCredits);
        kintoAppRegistry = IKintoAppRegistry(_kintoAppRegistry);
    }

    /**
     * @dev Upgrade calling `upgradeTo()`
     */
    function initialize() external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        _transferOwnership(msg.sender);
    }

    /**
     * @dev Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the factory is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        if (msg.sender != owner()) revert OnlyOwner();
    }

    /* ============ Basic Viewers ============ */

    function isKYC(address addr) external view override returns (bool) {
        return kintoID.isKYC(_getOwnerOrWallet(addr));
    }

    function isSanctionsSafe(address account) external view override returns (bool) {
        return kintoID.isSanctionsSafe(_getOwnerOrWallet(account));
    }

    function isSanctionsSafeIn(address account, uint16 _countryId) external view override returns (bool) {
        return kintoID.isSanctionsSafeIn(_getOwnerOrWallet(account), _countryId);
    }

    function isCompany(address account) external view override returns (bool) {
        return kintoID.isCompany(_getOwnerOrWallet(account));
    }

    function isIndividual(address account) external view override returns (bool) {
        return kintoID.isIndividual(_getOwnerOrWallet(account));
    }

    function hasTrait(address account, uint16 _traitId) external view returns (bool) {
        return kintoID.hasTrait(_getOwnerOrWallet(account), _traitId);
    }

    function hasTraits(address account, uint16[] memory _traitIds) public view returns (uint16[] memory) {
        address finalAddress = _getOwnerOrWallet(account);
        uint16[] memory results = new uint16[](_traitIds.length);
        for (uint256 i = 0; i < _traitIds.length; i++) {
            results[i] = kintoID.hasTrait(finalAddress, _traitIds[i]) ? 1 : 0;
        }
        return results;
    }

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

    function getDevApps(address wallet) external view override returns (IKintoAppRegistry.Metadata[] memory) {
        uint256 balance = IERC721Enumerable(address(kintoAppRegistry)).balanceOf(wallet);
        IKintoAppRegistry.Metadata[] memory apps = new IKintoAppRegistry.Metadata[](balance);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = IERC721Enumerable(address(kintoAppRegistry)).tokenOfOwnerByIndex(wallet, i);
            apps[i] = kintoAppRegistry.getAppMetadata(kintoAppRegistry.tokenIdToApp(tokenId));
        }
        return apps;
    }

    /**
     * @notice Retrieves the ERC20 token balances for a specific target address.
     * @dev This view function allows fetching balances for multiple tokens in a single call,
     *         which can save considerable gas over multiple calls.
     * @param tokens An array of token addresses to query balances for.
     * @param target The address whose balances will be queried.
     * @return balances An array of balances corresponding to the array of tokens provided.
     */
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

    function _getOwnerOrWallet(address addr) private view returns (address) {
        if (walletFactory.getWalletTimestamp(addr) > 0) {
            return IKintoWallet(payable(addr)).owners(0);
        }
        return addr;
    }
}

contract KYCViewerV13 is KYCViewer {
    constructor(address _kintoWalletFactory, address _faucet, address _engenCredits, address _kintoAppRegistry)
        KYCViewer(_kintoWalletFactory, _faucet, _engenCredits, _kintoAppRegistry)
    {}
}

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

    function isKYC(address _address) external view override returns (bool) {
        return kintoID.isKYC(_getFinalAddress(_address));
    }

    function isSanctionsSafe(address _account) external view override returns (bool) {
        return kintoID.isSanctionsSafe(_getFinalAddress(_account));
    }

    function isSanctionsSafeIn(address _account, uint16 _countryId) external view override returns (bool) {
        return kintoID.isSanctionsSafeIn(_getFinalAddress(_account), _countryId);
    }

    function isCompany(address _account) external view override returns (bool) {
        return kintoID.isCompany(_getFinalAddress(_account));
    }

    function isIndividual(address _account) external view override returns (bool) {
        return kintoID.isIndividual(_getFinalAddress(_account));
    }

    function hasTrait(address _account, uint8 _traitId) external view returns (bool) {
        return kintoID.hasTrait(_getFinalAddress(_account), _traitId);
    }

    function getWalletOwners(address _wallet) public view override returns (address[] memory owners) {
        // return owners if wallet exists and has a valid timestamp
        if (_wallet != address(0) && walletFactory.getWalletTimestamp(_wallet) > 0) {
            uint256 ownersCount = IKintoWallet(payable(_wallet)).getOwnersCount();
            owners = new address[](ownersCount);
            for (uint256 i = 0; i < ownersCount; i++) {
                owners[i] = IKintoWallet(payable(_wallet)).owners(i);
            }
        }
    }

    function getUserInfo(address _account, address payable _wallet)
        external
        view
        override
        returns (IKYCViewer.UserInfo memory info)
    {
        bool hasWallet = _wallet != address(0) && walletFactory.getWalletTimestamp(_wallet) > 0;
        info = IKYCViewer.UserInfo({
            ownerBalance: _account.balance,
            walletBalance: hasWallet ? _wallet.balance : 0,
            walletPolicy: hasWallet ? IKintoWallet(_wallet).signerPolicy() : 0,
            walletOwners: hasWallet ? getWalletOwners(_wallet) : new address[](0),
            claimedFaucet: faucet.claimed(_account),
            hasNFT: IERC721(address(kintoID)).balanceOf(_account) > 0,
            engenCreditsEarned: engenCredits.earnedCredits(_wallet),
            engenCreditsClaimed: IERC20(address(engenCredits)).balanceOf(_wallet),
            isKYC: kintoID.isKYC(_account),
            recoveryTs: hasWallet ? IKintoWallet(_wallet).inRecovery() : 0,
            insurancePolicy: hasWallet ? IKintoWallet(_wallet).insurancePolicy() : 0,
            hasValidInsurance: hasWallet
                ? (IKintoWallet(_wallet).insuranceTimestamp() + 365 days) >= block.timestamp
                : false,
            insuranceTimestamp: hasWallet ? IKintoWallet(_wallet).insuranceTimestamp() : 0,
            deployer: hasWallet ? kintoAppRegistry.walletToDeployer(_wallet) : address(0)
        });
    }

    function getDevApps(address _wallet) external view override returns (IKintoAppRegistry.Metadata[] memory) {
        uint256 balance = IERC721Enumerable(address(kintoAppRegistry)).balanceOf(_wallet);
        IKintoAppRegistry.Metadata[] memory apps = new IKintoAppRegistry.Metadata[](balance);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = IERC721Enumerable(address(kintoAppRegistry)).tokenOfOwnerByIndex(_wallet, i);
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

    function _getFinalAddress(address _address) private view returns (address) {
        if (walletFactory.getWalletTimestamp(_address) > 0) {
            return IKintoWallet(payable(_address)).owners(0);
        }
        return _address;
    }
}

contract KYCViewerV12 is KYCViewer {
    constructor(address _kintoWalletFactory, address _faucet, address _engenCredits, address _kintoAppRegistry)
        KYCViewer(_kintoWalletFactory, _faucet, _engenCredits, _kintoAppRegistry)
    {}
}

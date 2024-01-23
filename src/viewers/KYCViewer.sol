// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/IKintoID.sol";
import "../interfaces/IKintoWalletFactory.sol";
import "../interfaces/IKYCViewer.sol";

/**
 * @title KYCViewer
 * @dev A viewer class that helps developers to check if an address is KYC'd
 *      Abstracts complexity by checking both wallet and EOA.
 */
contract KYCViewer is Initializable, UUPSUpgradeable, OwnableUpgradeable, IKYCViewer {
    /* ============ State Variables ============ */

    IKintoWalletFactory public immutable override walletFactory;
    IKintoID public immutable override kintoID;

    /* ============ Events ============ */

    /* ============ Constructor & Upgrades ============ */
    constructor(address _kintoWalletFactory) {
        _disableInitializers();
        walletFactory = IKintoWalletFactory(_kintoWalletFactory);
        kintoID = walletFactory.kintoID();
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
        require(msg.sender == owner(), "only owner");
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

    /* ============ Helpers ============ */

    function _getFinalAddress(address _address) private view returns (address) {
        if (walletFactory.getWalletTimestamp(_address) > 0) {
            return IKintoWallet(payable(_address)).owners(0);
        }
        return _address;
    }
}

contract KYCViewerV2 is KYCViewer {
    constructor(address _kintoWalletFactory) KYCViewer(_kintoWalletFactory) {}
}

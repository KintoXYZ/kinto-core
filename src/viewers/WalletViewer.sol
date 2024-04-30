// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";

import "../interfaces/IKintoID.sol";
import "../interfaces/IKintoAppRegistry.sol";
import "../interfaces/IKintoWalletFactory.sol";
import "../interfaces/IKintoWallet.sol";
import "../interfaces/IWalletViewer.sol";
import "forge-std/console.sol";

/**
 * @title WalletViewer
 * @dev A viewer class that helps developers to check wallet and apps faster
 */
contract WalletViewer is Initializable, UUPSUpgradeable, OwnableUpgradeable, IWalletViewer {
    /* ============ State Variables ============ */

    IKintoWalletFactory public immutable override walletFactory;
    IKintoID public immutable override kintoID;
    IKintoAppRegistry public immutable override appRegistry;

    /* ============ Constructor & Upgrades ============ */
    constructor(address _kintoWalletFactory, address _appRegistry) {
        _disableInitializers();
        walletFactory = IKintoWalletFactory(_kintoWalletFactory);
        kintoID = walletFactory.kintoID();
        appRegistry = IKintoAppRegistry(_appRegistry);
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

    /**
     * @dev Fetches 50 applications from the registry
     * @param _index start index
     * @return address[50] list of 50 applications
     */
    function fetchAppAddresesFromIndex(uint256 _index) external view override returns (address[50] memory) {
        address[50] memory _appAddresses;
        for (uint256 i = 0; i < 50; i++) {
            _appAddresses[i] = appRegistry.tokenIdToApp(_index + i);
        }
        return _appAddresses;
    }

    /**
     * @dev Fetches 50 applications from the registry and filters the one that the user has approved
     * @param walletAddress address of the wallet
     * @param _index start index
     * @return WalletApp[50] list of 50 applications
     */
    function fetchUserAppAddressesFromIndex(address walletAddress, uint256 _index)
        external
        view
        override
        returns (WalletApp[50] memory)
    {
        WalletApp[50] memory _appAddresses;
        if (walletFactory.walletTs(walletAddress) == 0) {
            return _appAddresses;
        }
        for (uint256 i = 0; i < 50; i++) {
            address app = appRegistry.tokenIdToApp(_index + i);
            IKintoWallet wallet = IKintoWallet(walletAddress);
            if (wallet.appWhitelist(app)) {
                _appAddresses[i] = WalletApp(true, wallet.appSigner(app));
            }
        }
        return _appAddresses;
    }
}

contract WalletViewerV1 is WalletViewer {
    constructor(address _kintoWalletFactory, address _appRegistry) WalletViewer(_kintoWalletFactory, _appRegistry) {}
}

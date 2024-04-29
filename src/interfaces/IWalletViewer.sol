// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IKintoID.sol";
import "./IKintoWalletFactory.sol";
import "./IKintoAppRegistry.sol";

interface IWalletViewer {
    /* ============ Errors ============ */
    error OnlyOwner();

    /* ============ Structs ============ */

    struct WalletApp {
        bool whitelisted;
        address key;
    }

    /* ============ Basic Viewers ============ */

    function fetchAppAddresesFromIndex(uint256 _index) external view returns (address[50] memory);

    function fetchUserAppAddressesFromIndex(address walletAddress, uint256 _index)
        external
        view
        returns (WalletApp[50] memory);

    /* ============ Constants and attrs ============ */

    function kintoID() external view returns (IKintoID);

    function walletFactory() external view returns (IKintoWalletFactory);

    function appRegistry() external view returns (IKintoAppRegistry);
}

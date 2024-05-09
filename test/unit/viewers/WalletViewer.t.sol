// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "@kinto-core/wallet/KintoWallet.sol";
import "@kinto-core/wallet/KintoWalletFactory.sol";
import "@kinto-core/KintoID.sol";
import "@kinto-core/viewers/WalletViewer.sol";

import "@kinto-core/interfaces/IWalletViewer.sol";

import "@kinto-core-test/SharedSetup.t.sol";
import "@kinto-core-test/helpers/UUPSProxy.sol";

contract WalletViewerUpgraded is WalletViewer {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(address _kintoWalletFactory, address _appRegistry) WalletViewer(_kintoWalletFactory, _appRegistry) {}
}

contract WalletViewerTest is SharedSetup {
    function testUp() public view override {
        assertEq(_walletViewer.owner(), _owner);
        assertEq(address(_entryPoint.walletFactory()), address(_walletViewer.walletFactory()));
        assertEq(address(_walletFactory.kintoID()), address(_walletViewer.kintoID()));
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        WalletViewerUpgraded _implementationV2 =
            new WalletViewerUpgraded(address(_walletFactory), address(_kintoAppRegistry));
        vm.prank(_owner);
        _walletViewer.upgradeTo(address(_implementationV2));
        assertEq(WalletViewerUpgraded(address(_walletViewer)).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner(address someone) public {
        vm.assume(someone != _owner);
        WalletViewerUpgraded _implementationV2 =
            new WalletViewerUpgraded(address(_walletFactory), address(_kintoAppRegistry));
        vm.expectRevert(IWalletViewer.OnlyOwner.selector);
        vm.prank(someone);
        _walletViewer.upgradeTo(address(_implementationV2));
    }

    /* ============ Viewer tests ============ */

    function testFetchAppAddressesFromIndex() public view {
        address[50] memory apps = _walletViewer.fetchAppAddresesFromIndex(1);
        assertEq(_walletViewer.appRegistry().appCount(), 1);
        assertTrue(apps[0] != address(0));
        assertTrue(apps[1] == address(0));
    }

    function testFetchUserAppAddressesFromIndex() public view {
        IWalletViewer.WalletApp[50] memory apps = _walletViewer.fetchUserAppAddressesFromIndex(address(_kintoWallet), 1);
        assertEq(apps[0].whitelisted, true);
        assertEq(apps[0].key, address(0));
        assertEq(apps[1].whitelisted, false);
        assertEq(apps[1].key, address(0));
    }
}

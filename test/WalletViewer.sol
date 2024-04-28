// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/wallet/KintoWallet.sol";
import "../src/wallet/KintoWalletFactory.sol";
import "../src/KintoID.sol";
import "../src/viewers/WalletViewer.sol";

import "./SharedSetup.t.sol";
import "./helpers/UUPSProxy.sol";

contract WalletViewerUpgraded is WalletViewer {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(address _kintoWalletFactory, address _appRegistry) WalletViewer(_kintoWalletFactory, _appRegistry) {}
}

contract WalletViewerTest is SharedSetup {
    function testUp() public override {
        super.testUp();
        assertEq(_walletViewer.owner(), _owner);
        assertEq(address(_entryPoint.walletFactory()), address(_walletViewer.walletFactory()));
        assertEq(address(_walletFactory.kintoID()), address(_walletViewer.kintoID()));
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        WalletViewerUpgraded _implementationV2 = new WalletViewerUpgraded(address(_walletFactory), address(_kintoAppRegistry));
        vm.prank(_owner);
        _walletViewer.upgradeTo(address(_implementationV2));
        assertEq(WalletViewerUpgraded(address(_walletViewer)).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner(address someone) public {
        vm.assume(someone != _owner);
        WalletViewerUpgraded _implementationV2 = new WalletViewerUpgraded(address(_walletFactory), address(_kintoAppRegistry));
        vm.expectRevert(IWalletViewer.OnlyOwner.selector);
        vm.prank(someone);
        _walletViewer.upgradeTo(address(_implementationV2));
    }

    /* ============ Viewer tests ============ */

    function testIsKYC_WhenBothOwnerAndWallet() public view {
    }

    function testGetUserInfo() public view {

    }

}

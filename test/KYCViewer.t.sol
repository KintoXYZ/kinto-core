// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/wallet/KintoWallet.sol";
import "../src/wallet/KintoWalletFactory.sol";
import "../src/KintoID.sol";
import "../src/viewers/KYCViewer.sol";

import "./SharedSetup.t.sol";
import "./helpers/UUPSProxy.sol";

contract KYCViewerUpgraded is KYCViewer {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(address _kintoWalletFactory) KYCViewer(_kintoWalletFactory) {}
}

contract KYCViewerTest is SharedSetup {
    function testUp() public override {
        super.testUp();
        assertEq(_kycViewer.owner(), _owner);
        assertEq(address(_entryPoint.walletFactory()), address(_kycViewer.walletFactory()));
        assertEq(address(_walletFactory.kintoID()), address(_kycViewer.kintoID()));
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        KYCViewerUpgraded _implementationV2 = new KYCViewerUpgraded(address(_walletFactory));
        vm.prank(_owner);
        _kycViewer.upgradeTo(address(_implementationV2));
        assertEq(KYCViewerUpgraded(address(_kycViewer)).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner(address someone) public {
        vm.assume(someone != _owner);
        KYCViewerUpgraded _implementationV2 = new KYCViewerUpgraded(address(_walletFactory));
        vm.expectRevert("only owner");
        vm.prank(someone);
        _kycViewer.upgradeTo(address(_implementationV2));
    }

    /* ============ Viewer tests ============ */

    function testIsKYCBothOwnerAndWallet() public {
        assertEq(_kycViewer.isKYC(address(_kintoWallet)), _kycViewer.isKYC(_owner));
        assertEq(_kycViewer.isIndividual(address(_kintoWallet)), _kycViewer.isIndividual(_owner));
        assertEq(_kycViewer.isCompany(address(_kintoWallet)), false);
        assertEq(_kycViewer.hasTrait(address(_kintoWallet), 6), false);
        assertEq(_kycViewer.isSanctionsSafe(address(_kintoWallet)), true);
        assertEq(_kycViewer.isSanctionsSafeIn(address(_kintoWallet), 1), true);
    }
}

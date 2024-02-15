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

    constructor(address _kintoWalletFactory, address _faucet) KYCViewer(_kintoWalletFactory, _faucet) {}
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
        KYCViewerUpgraded _implementationV2 = new KYCViewerUpgraded(address(_walletFactory), address(_faucet));
        vm.prank(_owner);
        _kycViewer.upgradeToAndCall(address(_implementationV2), bytes(""));
        assertEq(KYCViewerUpgraded(address(_kycViewer)).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner(address someone) public {
        vm.assume(someone != _owner);
        KYCViewerUpgraded _implementationV2 = new KYCViewerUpgraded(address(_walletFactory), address(_faucet));
        vm.expectRevert(IKYCViewer.OnlyOwner.selector);
        vm.prank(someone);
        _kycViewer.upgradeToAndCall(address(_implementationV2), bytes(""));
    }

    /* ============ Viewer tests ============ */

    function testIsKYC_WhenBothOwnerAndWallet() public {
        assertEq(_kycViewer.isKYC(address(_kintoWallet)), _kycViewer.isKYC(_owner));
        assertEq(_kycViewer.isIndividual(address(_kintoWallet)), _kycViewer.isIndividual(_owner));
        assertEq(_kycViewer.isCompany(address(_kintoWallet)), false);
        assertEq(_kycViewer.hasTrait(address(_kintoWallet), 6), false);
        assertEq(_kycViewer.isSanctionsSafe(address(_kintoWallet)), true);
        assertEq(_kycViewer.isSanctionsSafeIn(address(_kintoWallet), 1), true);
    }

    function testGetUserInfo() public {
        IKYCViewer.UserInfo memory userInfo = _kycViewer.getUserInfo(_owner, payable(address(_kintoWallet)));

        // verify properties
        assertEq(userInfo.ownerBalance, _owner.balance);
        assertEq(userInfo.walletBalance, address(_kintoWallet).balance);
        assertEq(userInfo.walletPolicy, _kintoWallet.signerPolicy());
        assertEq(userInfo.walletOwners.length, 1);
        assertEq(userInfo.claimedFaucet, false);
        assertEq(userInfo.hasNFT, true);
        assertEq(userInfo.isKYC, _kycViewer.isKYC(_owner));
    }

    function testGetUserInfo_WhenWalletDoesNotExist() public {
        IKYCViewer.UserInfo memory userInfo = _kycViewer.getUserInfo(_owner, payable(address(123)));

        // verify properties
        assertEq(userInfo.ownerBalance, _owner.balance);
        assertEq(userInfo.walletBalance, 0);
        assertEq(userInfo.walletPolicy, 0);
        assertEq(userInfo.walletOwners.length, 0);
        assertEq(userInfo.claimedFaucet, false);
        assertEq(userInfo.hasNFT, true);
        assertEq(userInfo.isKYC, _kycViewer.isKYC(_owner));
    }

    function testGetUserInfo_WhenAccountDoesNotExist() public {
        IKYCViewer.UserInfo memory userInfo = _kycViewer.getUserInfo(address(111), payable(address(123)));

        // verify properties
        assertEq(userInfo.ownerBalance, 0);
        assertEq(userInfo.walletBalance, 0);
        assertEq(userInfo.walletPolicy, 0);
        assertEq(userInfo.walletOwners.length, 0);
        assertEq(userInfo.claimedFaucet, false);
        assertEq(userInfo.hasNFT, false);
        assertEq(userInfo.isKYC, _kycViewer.isKYC(address(111)));
    }
}

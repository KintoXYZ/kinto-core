// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/wallet/KintoWallet.sol";
import "../src/wallet/KintoWalletFactory.sol";
import "../src/KintoID.sol";
import "../src/viewers/KYCViewer.sol";

import "./helpers/UserOp.sol";
import "./helpers/UUPSProxy.sol";
import {AATestScaffolding} from "./helpers/AATestScaffolding.sol";

contract KYCViewerV2 is KYCViewer {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(address _kintoWalletFactory) KYCViewer(_kintoWalletFactory) {}
}

contract KYCViewerTest is UserOp, AATestScaffolding {
    uint256 _chainID = 1;

    UUPSProxy _proxyViewer;
    KYCViewer _implkycViewer;
    KYCViewerV2 _implkycViewerV2;
    KYCViewer _kycViewer;
    KYCViewerV2 _kycViewer2;

    function setUp() public {
        vm.chainId(_chainID);
        vm.startPrank(address(1));
        _owner.transfer(1e18);
        vm.stopPrank();
        deployAAScaffolding(_owner, 1, _kycProvider, _recoverer);
        vm.startPrank(_owner);
        _implkycViewer = new KYCViewer{salt: 0}(address(_walletFactory));
        // deploy _proxy contract and point it to _implementation
        _proxyViewer = new UUPSProxy{salt: 0}(address(_implkycViewer), "");
        // wrap in ABI to support easier calls
        _kycViewer = KYCViewer(address(_proxyViewer));
        // Initialize kyc viewer _proxy
        _kycViewer.initialize();
        vm.stopPrank();
    }

    function testUp() public {
        console.log("address owner", address(_owner));
        assertEq(_kycViewer.owner(), _owner);
        assertEq(address(_entryPoint.walletFactory()), address(_kycViewer.walletFactory()));
        address kintoID = address(_kycViewer.kintoID());
        assertEq(address(_walletFactory.kintoID()), kintoID);
    }

    /* ============ Upgrade Tests ============ */

    function testOwnerCanUpgradeViewer() public {
        vm.startPrank(_owner);
        KYCViewerV2 _implementationV2 = new KYCViewerV2(address(_walletFactory));
        _kycViewer.upgradeTo(address(_implementationV2));
        // re-wrap the _proxy
        _kycViewer2 = KYCViewerV2(address(_kycViewer));
        assertEq(_kycViewer2.newFunction(), 1);
        vm.stopPrank();
    }

    function test_RevertWhen_OthersCannotUpgradeFactory() public {
        KYCViewerV2 _implementationV2 = new KYCViewerV2(address(_walletFactory));
        vm.expectRevert("only owner");
        _kycViewer.upgradeTo(address(_implementationV2));
    }

    /* ============ Viewer Tests ============ */

    function testIsKYCBothOwnerAndWallet() public {
        assertEq(_kycViewer.isKYC(address(_kintoWallet)), _kycViewer.isKYC(_owner));
        assertEq(_kycViewer.isIndividual(address(_kintoWallet)), _kycViewer.isIndividual(_owner));
        assertEq(_kycViewer.isCompany(address(_kintoWallet)), false);
        assertEq(_kycViewer.hasTrait(address(_kintoWallet), 6), false);
    }
}

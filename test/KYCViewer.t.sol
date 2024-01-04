// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/wallet/KintoWallet.sol";
import "../src/wallet/KintoWalletFactory.sol";
import "../src/paymasters/SponsorPaymaster.sol";
import "../src/KintoID.sol";
import "../src/viewers/KYCViewer.sol";
import {UserOp} from "./helpers/UserOp.sol";
import {UUPSProxy} from "./helpers/UUPSProxy.sol";
import {AATestScaffolding} from "./helpers/AATestScaffolding.sol";
import {Create2Helper} from "./helpers/Create2Helper.sol";
import "./helpers/KYCSignature.sol";

import "@aa/interfaces/IAccount.sol";
import "@aa/interfaces/INonceManager.sol";
import "@aa/interfaces/IEntryPoint.sol";
import "@aa/core/EntryPoint.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract KYCViewerV2 is KYCViewer {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(address _kintoWalletFactory) KYCViewer(_kintoWalletFactory) {}
}

contract KYCViewerTest is Create2Helper, UserOp, AATestScaffolding {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    uint256 _chainID = 1;

    address payable _owner = payable(vm.addr(1));
    address _secondowner = address(2);
    address payable _user = payable(vm.addr(3));
    address _user2 = address(4);
    address _upgrader = address(5);
    address _kycProvider = address(6);
    address _recoverer = address(7);
    address payable _funder = payable(vm.addr(8));
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
        deployAAScaffolding(_owner, _kycProvider, _recoverer);
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

    function testFailOthersCannotUpgradeFactory() public {
        KYCViewerV2 _implementationV2 = new KYCViewerV2(address(_walletFactory));
        _kycViewer.upgradeTo(address(_implementationV2));
        // re-wrap the _proxy
        _kycViewer2 = KYCViewerV2(address(_kycViewer));
        assertEq(_kycViewer2.newFunction(), 1);
    }

    /* ============ Viewer Tests ============ */

    function testIsKYCBothOwnerAndWallet() public {
        assertEq(_kycViewer.isKYC(address(_kintoWalletv1)), _kycViewer.isKYC(_owner));
        assertEq(_kycViewer.isIndividual(address(_kintoWalletv1)), _kycViewer.isIndividual(_owner));
        assertEq(_kycViewer.isCompany(address(_kintoWalletv1)), false);
        assertEq(_kycViewer.hasTrait(address(_kintoWalletv1), 6), false);
    }
}

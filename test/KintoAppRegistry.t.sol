// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/apps/KintoAppRegistry.sol";

import "./helpers/UserOp.sol";
import {AATestScaffolding} from "./helpers/AATestScaffolding.sol";

contract KintoAppRegistryV2 is KintoAppRegistry {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(IKintoWalletFactory _walletFactory) KintoAppRegistry(_walletFactory) {}
}

contract KintoAppRegistryTest is UserOp, AATestScaffolding {
    uint256 _chainID = 1;

    KintoAppRegistryV2 _implkintoAppV2;
    KintoAppRegistryV2 _kintoApp2;

    function setUp() public {
        vm.chainId(_chainID);
        vm.startPrank(address(1));
        _owner.transfer(1e18);
        vm.stopPrank();
        deployAAScaffolding(_owner, 1, _kycProvider, _recoverer);
    }

    function testUp() public {
        console.log("address owner", address(_owner));
        assertEq(_kintoAppRegistry.owner(), _owner);
        assertEq(_kintoAppRegistry.name(), "Kinto APP");
        assertEq(_kintoAppRegistry.symbol(), "KINTOAPP");
        assertEq(_kintoAppRegistry.RATE_LIMIT_PERIOD(), 1 minutes);
        assertEq(_kintoAppRegistry.RATE_LIMIT_THRESHOLD(), 10);
        assertEq(_kintoAppRegistry.GAS_LIMIT_PERIOD(), 30 days);
        assertEq(_kintoAppRegistry.GAS_LIMIT_THRESHOLD(), 1e16);
    }

    /* ============ Upgrade Tests ============ */

    function testOwnerCanUpgradeApp() public {
        vm.startPrank(_owner);
        KintoAppRegistryV2 _implementationV2 = new KintoAppRegistryV2(_walletFactory);
        _kintoAppRegistry.upgradeTo(address(_implementationV2));
        // re-wrap the _proxy
        _kintoApp2 = KintoAppRegistryV2(address(_kintoAppRegistry));
        assertEq(_kintoApp2.newFunction(), 1);
        vm.stopPrank();
    }

    function test_RevertWhen_OthersCannotUpgradeAppRegistry() public {
        KintoAppRegistryV2 _implementationV2 = new KintoAppRegistryV2(_walletFactory);
        vm.expectRevert("Ownable: caller is not the owner");
        _kintoAppRegistry.upgradeTo(address(_implementationV2));
    }

    /* ============ App Tests & Viewers ============ */

    function testRegisterApp(string memory name, address parentContract) public {
        vm.startPrank(_user);
        assertEq(_kintoAppRegistry.appCount(), 0);
        address[] memory appContracts = new address[](1);
        appContracts[0] = address(7);
        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = _kintoAppRegistry.RATE_LIMIT_PERIOD();
        appLimits[1] = _kintoAppRegistry.RATE_LIMIT_THRESHOLD();
        appLimits[2] = _kintoAppRegistry.GAS_LIMIT_PERIOD();
        appLimits[3] = _kintoAppRegistry.GAS_LIMIT_THRESHOLD();
        _kintoAppRegistry.registerApp(
            name, parentContract, appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]]
        );
        assertEq(_kintoAppRegistry.balanceOf(_user), 1);
        assertEq(_kintoAppRegistry.appCount(), 1);
        IKintoAppRegistry.Metadata memory metadata = _kintoAppRegistry.getAppMetadata(parentContract);
        assertEq(metadata.name, name);
        assertEq(metadata.dsaEnabled, false);
        assertEq(_kintoAppRegistry.ownerOf(metadata.tokenId), _user);
        assertEq(metadata.rateLimitPeriod, appLimits[0]);
        assertEq(metadata.rateLimitNumber, appLimits[1]);
        assertEq(metadata.gasLimitPeriod, appLimits[2]);
        assertEq(metadata.gasLimitCost, appLimits[3]);
        assertEq(_kintoAppRegistry.isContractSponsored(parentContract, address(7)), true);
        assertEq(_kintoAppRegistry.getSponsor(address(7)), parentContract);
        uint256[4] memory limits = _kintoAppRegistry.getContractLimits(address(7));
        assertEq(limits[0], appLimits[0]);
        assertEq(limits[1], appLimits[1]);
        assertEq(limits[2], appLimits[2]);
        assertEq(limits[3], appLimits[3]);
        limits = _kintoAppRegistry.getContractLimits(parentContract);
        assertEq(limits[0], appLimits[0]);
        assertEq(limits[1], appLimits[1]);
        assertEq(limits[2], appLimits[2]);
        assertEq(limits[3], appLimits[3]);
        metadata = _kintoAppRegistry.getAppMetadata(address(7));
        assertEq(metadata.name, name);
        vm.stopPrank();
    }

    function testRegisterAppAndUpdate(string memory name, address parentContract) public {
        vm.startPrank(_user);
        address[] memory appContracts = new address[](1);
        appContracts[0] = address(8);
        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = _kintoAppRegistry.RATE_LIMIT_PERIOD();
        appLimits[1] = _kintoAppRegistry.RATE_LIMIT_THRESHOLD();
        appLimits[2] = _kintoAppRegistry.GAS_LIMIT_PERIOD();
        appLimits[3] = _kintoAppRegistry.GAS_LIMIT_THRESHOLD();
        _kintoAppRegistry.registerApp(
            name, parentContract, appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]]
        );
        _kintoAppRegistry.updateMetadata(
            "test2", parentContract, appContracts, [uint256(1), uint256(1), uint256(1), uint256(1)]
        );
        IKintoAppRegistry.Metadata memory metadata = _kintoAppRegistry.getAppMetadata(parentContract);
        assertEq(metadata.name, "test2");
        assertEq(metadata.dsaEnabled, false);
        assertEq(metadata.rateLimitPeriod, 1);
        assertEq(metadata.rateLimitNumber, 1);
        assertEq(metadata.gasLimitPeriod, 1);
        assertEq(metadata.gasLimitCost, 1);
        assertEq(_kintoAppRegistry.isContractSponsored(parentContract, address(7)), false);
        assertEq(_kintoAppRegistry.isContractSponsored(parentContract, address(8)), true);
        vm.stopPrank();
    }

    /* ============ DSA Test ============ */

    function testOwnerCanEnableDSA() public {
        vm.startPrank(_owner);
        address parentContract = address(_engenCredits);
        address[] memory appContracts = new address[](1);
        appContracts[0] = address(8);
        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = _kintoAppRegistry.RATE_LIMIT_PERIOD();
        appLimits[1] = _kintoAppRegistry.RATE_LIMIT_THRESHOLD();
        appLimits[2] = _kintoAppRegistry.GAS_LIMIT_PERIOD();
        appLimits[3] = _kintoAppRegistry.GAS_LIMIT_THRESHOLD();
        _kintoAppRegistry.registerApp(
            "", parentContract, appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]]
        );
        _kintoAppRegistry.enableDSA(parentContract);
        IKintoAppRegistry.Metadata memory metadata = _kintoAppRegistry.getAppMetadata(parentContract);
        assertEq(metadata.dsaEnabled, true);
        vm.stopPrank();
    }

    function test_Revert_When_User_TriesToEnableDSA() public {
        vm.startPrank(_user);
        address parentContract = address(_engenCredits);
        address[] memory appContracts = new address[](1);
        appContracts[0] = address(8);
        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = _kintoAppRegistry.RATE_LIMIT_PERIOD();
        appLimits[1] = _kintoAppRegistry.RATE_LIMIT_THRESHOLD();
        appLimits[2] = _kintoAppRegistry.GAS_LIMIT_PERIOD();
        appLimits[3] = _kintoAppRegistry.GAS_LIMIT_THRESHOLD();
        _kintoAppRegistry.registerApp(
            "", parentContract, appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]]
        );
        vm.expectRevert("Ownable: caller is not the owner");
        _kintoAppRegistry.enableDSA(parentContract);
    }

    /* ============ Sponsored Contracts Test ============ */

    function testAppCreatorCanSetSponsoredContracts() public {
        vm.startPrank(_user);
        address parentContract = address(_engenCredits);
        address[] memory appContracts = new address[](1);
        appContracts[0] = address(8);
        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = _kintoAppRegistry.RATE_LIMIT_PERIOD();
        appLimits[1] = _kintoAppRegistry.RATE_LIMIT_THRESHOLD();
        appLimits[2] = _kintoAppRegistry.GAS_LIMIT_PERIOD();
        appLimits[3] = _kintoAppRegistry.GAS_LIMIT_THRESHOLD();
        _kintoAppRegistry.registerApp(
            "", parentContract, appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]]
        );
        address[] memory contracts = new address[](2);
        contracts[0] = address(8);
        contracts[1] = address(9);
        bool[] memory flags = new bool[](2);
        flags[0] = false;
        flags[1] = true;
        _kintoAppRegistry.setSponsoredContracts(parentContract, contracts, flags);
        assertEq(_kintoAppRegistry.isContractSponsored(parentContract, address(8)), true); // child contracts always sponsored
        assertEq(_kintoAppRegistry.isContractSponsored(parentContract, address(9)), true);
        assertEq(_kintoAppRegistry.isContractSponsored(parentContract, address(10)), false);
        vm.stopPrank();
    }

    function test_Revert_When_NotCreator_TriesToSetSponsoredContracts() public {
        vm.startPrank(_user);
        address parentContract = address(_engenCredits);
        address[] memory appContracts = new address[](1);
        appContracts[0] = address(8);
        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = _kintoAppRegistry.RATE_LIMIT_PERIOD();
        appLimits[1] = _kintoAppRegistry.RATE_LIMIT_THRESHOLD();
        appLimits[2] = _kintoAppRegistry.GAS_LIMIT_PERIOD();
        appLimits[3] = _kintoAppRegistry.GAS_LIMIT_THRESHOLD();
        _kintoAppRegistry.registerApp(
            "", parentContract, appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]]
        );
        address[] memory contracts = new address[](2);
        contracts[0] = address(8);
        contracts[1] = address(9);
        bool[] memory flags = new bool[](2);
        flags[0] = false;
        flags[1] = true;
        vm.startPrank(_user2);
        vm.expectRevert("Only developer can set sponsored contracts");
        _kintoAppRegistry.setSponsoredContracts(parentContract, contracts, flags);
        vm.stopPrank();
    }

    /* ============ Transfer Test ============ */

    function test_RevertWhen_TransfersAreDisabled() public {
        vm.startPrank(_user);
        address parentContract = address(_engenCredits);
        address[] memory appContracts = new address[](1);
        appContracts[0] = address(8);
        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = _kintoAppRegistry.RATE_LIMIT_PERIOD();
        appLimits[1] = _kintoAppRegistry.RATE_LIMIT_THRESHOLD();
        appLimits[2] = _kintoAppRegistry.GAS_LIMIT_PERIOD();
        appLimits[3] = _kintoAppRegistry.GAS_LIMIT_THRESHOLD();
        _kintoAppRegistry.registerApp(
            "", parentContract, appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]]
        );
        uint256 tokenIdx = _kintoAppRegistry.tokenOfOwnerByIndex(_user, 0);
        vm.expectRevert("Only mint transfers are allowed");
        _kintoAppRegistry.safeTransferFrom(_user, _user2, tokenIdx);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/apps/KintoAppRegistry.sol";

import "./SharedSetup.t.sol";

contract KintoAppRegistryV2 is KintoAppRegistry {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(IKintoWalletFactory _walletFactory) KintoAppRegistry(_walletFactory) {}
}

contract KintoAppRegistryTest is SharedSetup {
    function testUp() public override {
        super.testUp();
        useHarness();

        assertEq(_kintoAppRegistry.owner(), _owner);
        assertEq(_kintoAppRegistry.name(), "Kinto APP");
        assertEq(_kintoAppRegistry.symbol(), "KINTOAPP");
        assertEq(_kintoAppRegistry.RATE_LIMIT_PERIOD(), 1 minutes);
        assertEq(_kintoAppRegistry.RATE_LIMIT_THRESHOLD(), 10);
        assertEq(_kintoAppRegistry.GAS_LIMIT_PERIOD(), 30 days);
        assertEq(_kintoAppRegistry.GAS_LIMIT_THRESHOLD(), 1e16);
        assertEq(
            KintoAppRegistryHarness(address(_kintoAppRegistry)).exposed_baseURI(),
            "https://kinto.xyz/metadata/kintoapp/"
        );
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        vm.startPrank(_owner);

        KintoAppRegistryV2 _implementationV2 = new KintoAppRegistryV2(_walletFactory);
        _kintoAppRegistry.upgradeTo(address(_implementationV2));
        assertEq(KintoAppRegistryV2(address(_kintoAppRegistry)).newFunction(), 1);

        vm.stopPrank();
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner() public {
        KintoAppRegistryV2 _implementationV2 = new KintoAppRegistryV2(_walletFactory);
        vm.expectRevert("Ownable: caller is not the owner");
        _kintoAppRegistry.upgradeTo(address(_implementationV2));
    }

    /* ============ App tests & Viewers ============ */

    function testRegisterApp(string memory name, address parentContract) public {
        address[] memory appContracts = new address[](1);
        appContracts[0] = address(7);

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = _kintoAppRegistry.RATE_LIMIT_PERIOD();
        appLimits[1] = _kintoAppRegistry.RATE_LIMIT_THRESHOLD();
        appLimits[2] = _kintoAppRegistry.GAS_LIMIT_PERIOD();
        appLimits[3] = _kintoAppRegistry.GAS_LIMIT_THRESHOLD();

        // register app
        uint256 balanceBefore = _kintoAppRegistry.balanceOf(_user);
        uint256 appsCountBefore = _kintoAppRegistry.appCount();

        vm.prank(_user);
        _kintoAppRegistry.registerApp(
            name, parentContract, appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]]
        );

        assertEq(_kintoAppRegistry.balanceOf(_user), balanceBefore + 1);
        assertEq(_kintoAppRegistry.appCount(), appsCountBefore + 1);

        // check app metadata
        IKintoAppRegistry.Metadata memory metadata = _kintoAppRegistry.getAppMetadata(parentContract);
        assertEq(metadata.name, name);
        assertEq(metadata.dsaEnabled, false);
        assertEq(_kintoAppRegistry.ownerOf(metadata.tokenId), _user);
        assertEq(metadata.rateLimitPeriod, appLimits[0]);
        assertEq(metadata.rateLimitNumber, appLimits[1]);
        assertEq(metadata.gasLimitPeriod, appLimits[2]);
        assertEq(metadata.gasLimitCost, appLimits[3]);
        assertEq(_kintoAppRegistry.isSponsored(parentContract, address(7)), true);
        assertEq(_kintoAppRegistry.getSponsor(address(7)), parentContract);

        // check child limits
        uint256[4] memory limits = _kintoAppRegistry.getContractLimits(address(7));
        assertEq(limits[0], appLimits[0]);
        assertEq(limits[1], appLimits[1]);
        assertEq(limits[2], appLimits[2]);
        assertEq(limits[3], appLimits[3]);

        // check app contracts
        limits = _kintoAppRegistry.getContractLimits(parentContract);
        assertEq(limits[0], appLimits[0]);
        assertEq(limits[1], appLimits[1]);
        assertEq(limits[2], appLimits[2]);
        assertEq(limits[3], appLimits[3]);

        // check child metadata
        metadata = _kintoAppRegistry.getAppMetadata(address(7));
        assertEq(metadata.name, name);
    }

    function testRegisterApp_RevertWhen_ChildrenIsWallet(string memory name, address parentContract) public {
        uint256[4] memory appLimits = [uint256(0), uint256(0), uint256(0), uint256(0)];
        address[] memory appContracts = new address[](1);
        appContracts[0] = address(_kintoWallet);

        // register app
        vm.expectRevert("Wallets can not be registered");
        _kintoAppRegistry.registerApp(name, parentContract, appContracts, appLimits);
    }

    function testRegisterApp_RevertWhen_AlreadyRegistered() public {
        // register app
        string memory name = "app";
        address parentContract = address(_engenCredits);
        uint256[4] memory appLimits = [uint256(0), uint256(0), uint256(0), uint256(0)];
        address[] memory appContracts = new address[](0);

        vm.prank(_owner);
        _kintoAppRegistry.registerApp(name, parentContract, appContracts, appLimits);

        // try to register again
        vm.expectRevert("App already registered");
        _kintoAppRegistry.registerApp(name, parentContract, appContracts, appLimits);
    }

    function testRegisterApp_RevertWhen_ParentIsChild() public {
        // register app with child address 2
        string memory name = "app";
        address parentContract = address(_engenCredits);
        uint256[4] memory appLimits = [uint256(0), uint256(0), uint256(0), uint256(0)];
        address[] memory appContracts = new address[](1);
        appContracts[0] = address(2);

        vm.prank(_owner);
        _kintoAppRegistry.registerApp(name, parentContract, appContracts, appLimits);

        // registering app "app2" with parent address 2 should revert
        parentContract = address(2);
        appContracts = new address[](0);
        vm.expectRevert("Parent contract already registered as a child");
        _kintoAppRegistry.registerApp(name, parentContract, appContracts, appLimits);
    }

    function testUpdateMetadata(string memory name, address parentContract) public {
        address[] memory appContracts = new address[](1);
        appContracts[0] = address(8);

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = _kintoAppRegistry.RATE_LIMIT_PERIOD();
        appLimits[1] = _kintoAppRegistry.RATE_LIMIT_THRESHOLD();
        appLimits[2] = _kintoAppRegistry.GAS_LIMIT_PERIOD();
        appLimits[3] = _kintoAppRegistry.GAS_LIMIT_THRESHOLD();

        // register app
        vm.prank(_user);
        _kintoAppRegistry.registerApp(
            name, parentContract, appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]]
        );

        // update app
        vm.prank(_user);
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
        assertEq(_kintoAppRegistry.isSponsored(parentContract, address(7)), false);
        assertEq(_kintoAppRegistry.isSponsored(parentContract, address(8)), true);
    }

    function testUpdateMetadata_RevertWhen_CallerIsNotDeveloper(string memory name, address parentContract) public {
        registerApp(_owner, name, parentContract);

        // update app
        address[] memory appContracts = new address[](0);
        vm.prank(_user);
        vm.expectRevert("Only developer can update metadata");
        _kintoAppRegistry.updateMetadata(
            "test2", parentContract, appContracts, [uint256(1), uint256(1), uint256(1), uint256(1)]
        );
    }

    /* ============ DSA Test ============ */

    function testEnableDSA_WhenCallerIsOwner() public {
        registerApp(_owner, "app", address(_engenCredits));

        vm.prank(_owner);
        _kintoAppRegistry.enableDSA(address(_engenCredits));

        IKintoAppRegistry.Metadata memory metadata = _kintoAppRegistry.getAppMetadata(address(_engenCredits));
        assertEq(metadata.dsaEnabled, true);
    }

    function testEnableDSA_RevertWhen_CallerIsNotOwner() public {
        registerApp(_owner, "app", address(_engenCredits));

        vm.expectRevert("Ownable: caller is not the owner");
        _kintoAppRegistry.enableDSA(address(_engenCredits));
    }

    function testEnableDSA_RevertWhen_AlreadyEnabled() public {
        registerApp(_owner, "app", address(_engenCredits));
        vm.prank(_owner);
        _kintoAppRegistry.enableDSA(address(_engenCredits));

        vm.expectRevert("DSA already enabled");
        vm.prank(_owner);
        _kintoAppRegistry.enableDSA(address(_engenCredits));
    }

    /* ============ Sponsored Contracts Test ============ */

    function testSetSponsoredContracts() public {
        registerApp(_owner, "app", address(_engenCredits));

        address[] memory contracts = new address[](2);
        contracts[0] = address(8);
        contracts[1] = address(9);

        bool[] memory flags = new bool[](2);
        flags[0] = false;
        flags[1] = true;

        vm.prank(_owner);
        _kintoAppRegistry.setSponsoredContracts(address(_engenCredits), contracts, flags);

        assertEq(_kintoAppRegistry.isSponsored(address(_engenCredits), address(8)), false);
        assertEq(_kintoAppRegistry.isSponsored(address(_engenCredits), address(9)), true);
        assertEq(_kintoAppRegistry.isSponsored(address(_engenCredits), address(10)), false);
    }

    function testSetSponsoredContracts_RevertWhen_CallerIsNotCreator() public {
        registerApp(_owner, "app", address(_engenCredits));

        address[] memory contracts = new address[](2);
        contracts[0] = address(8);
        contracts[1] = address(9);

        bool[] memory flags = new bool[](2);
        flags[0] = false;
        flags[1] = true;

        vm.prank(_user);
        vm.expectRevert("Only developer can set sponsored contracts");
        _kintoAppRegistry.setSponsoredContracts(address(_engenCredits), contracts, flags);
    }

    function testSetSponsoredContracts_RevertWhen_LengthMismatch() public {
        registerApp(_owner, "app", address(_engenCredits));

        address[] memory contracts = new address[](1);
        contracts[0] = address(8);

        bool[] memory flags = new bool[](2);
        flags[0] = false;
        flags[1] = true;

        vm.expectRevert("Invalid input");
        _kintoAppRegistry.setSponsoredContracts(address(_engenCredits), contracts, flags);
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

    /* ============ Supports Interface tests ============ */

    function testSupportsInterface() public {
        bytes4 InterfaceERC721Upgradeable = bytes4(keccak256("balanceOf(address)"))
            ^ bytes4(keccak256("ownerOf(uint256)")) ^ bytes4(keccak256("safeTransferFrom(address,address,uint256,bytes)"))
            ^ bytes4(keccak256("safeTransferFrom(address,address,uint256)"))
            ^ bytes4(keccak256("transferFrom(address,address,uint256)")) ^ bytes4(keccak256("approve(address,uint256)"))
            ^ bytes4(keccak256("setApprovalForAll(address,bool)")) ^ bytes4(keccak256("getApproved(uint256)"))
            ^ bytes4(keccak256("isApprovedForAll(address,address)"));

        assertTrue(_kintoID.supportsInterface(InterfaceERC721Upgradeable));
    }
}

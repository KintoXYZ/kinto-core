// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@kinto-core/apps/KintoAppRegistry.sol";
import "@kinto-core/interfaces/IKintoAppRegistry.sol";

import "@kinto-core-test/SharedSetup.t.sol";

contract KintoAppRegistryV2 is KintoAppRegistry {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(IKintoWalletFactory _walletFactory) KintoAppRegistry(_walletFactory) {}
}

contract KintoAppRegistryTest is SharedSetup {
    address public constant CREATE2 = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

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

    /* ============ Upgrade ============ */

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

    function testRegisterApp() public {
        string memory name = "app";
        address parentContract = address(123);

        approveKYC(_kycProvider, _user, _userPk);

        address[] memory appContracts = new address[](1);
        appContracts[0] = address(7);

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = _kintoAppRegistry.RATE_LIMIT_PERIOD();
        appLimits[1] = _kintoAppRegistry.RATE_LIMIT_THRESHOLD();
        appLimits[2] = _kintoAppRegistry.GAS_LIMIT_PERIOD();
        appLimits[3] = _kintoAppRegistry.GAS_LIMIT_THRESHOLD();

        // register app
        uint256 balanceBefore = _kintoAppRegistry.balanceOf(address(_kintoWallet));
        uint256 appsCountBefore = _kintoAppRegistry.appCount();

        address[] memory eoas = new address[](1);
        eoas[0] = address(44);

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(
            name, parentContract, appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]], eoas
        );

        assertEq(_kintoAppRegistry.balanceOf(address(_kintoWallet)), balanceBefore + 1);
        assertEq(_kintoAppRegistry.appCount(), appsCountBefore + 1);

        // check eoas
        assertEq(_kintoAppRegistry.devEoaToApp(address(44)), parentContract);

        // check app metadata
        IKintoAppRegistry.Metadata memory metadata = _kintoAppRegistry.getAppMetadata(parentContract);
        assertEq(metadata.name, name);
        assertEq(metadata.dsaEnabled, false);
        assertEq(_kintoAppRegistry.ownerOf(metadata.tokenId), address(_kintoWallet));
        assertEq(metadata.rateLimitPeriod, appLimits[0]);
        assertEq(metadata.rateLimitNumber, appLimits[1]);
        assertEq(metadata.gasLimitPeriod, appLimits[2]);
        assertEq(metadata.gasLimitCost, appLimits[3]);
        assertEq(_kintoAppRegistry.isSponsored(parentContract, address(7)), true);
        assertEq(_kintoAppRegistry.getSponsor(address(7)), parentContract);
        assertEq(metadata.devEOAs[0], eoas[0]);

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

    function testRegisterApp_RevertWhen_ChildrenIsWallet() public {
        approveKYC(_kycProvider, _user, _userPk);

        uint256[4] memory appLimits = [uint256(0), uint256(0), uint256(0), uint256(0)];
        address[] memory appContracts = new address[](1);
        appContracts[0] = address(_kintoWallet);

        // register app
        vm.expectRevert(IKintoAppRegistry.CannotRegisterWallet.selector);
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp("app", address(123), appContracts, appLimits, new address[](0));
    }

    function testRegisterApp_RevertWhen_AlreadyRegistered() public {
        // register app
        string memory name = "app";
        address parentContract = address(_engenCredits);
        uint256[4] memory appLimits = [uint256(0), uint256(0), uint256(0), uint256(0)];
        address[] memory appContracts = new address[](0);

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(name, parentContract, appContracts, appLimits, new address[](0));

        // try to register again
        vm.expectRevert(IKintoAppRegistry.AlreadyRegistered.selector);
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(name, parentContract, appContracts, appLimits, new address[](0));
    }

    function testRegisterApp_RevertWhen_ParentIsChild() public {
        // register app with child address 2
        string memory name = "app";
        address parentContract = address(_engenCredits);
        uint256[4] memory appLimits = [uint256(0), uint256(0), uint256(0), uint256(0)];
        address[] memory appContracts = new address[](1);
        appContracts[0] = address(2);

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(name, parentContract, appContracts, appLimits, new address[](0));

        // registering app "app2" with parent address 2 should revert
        parentContract = address(2);
        appContracts = new address[](0);
        vm.expectRevert(IKintoAppRegistry.ParentAlreadyChild.selector);
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(name, parentContract, appContracts, appLimits, new address[](0));
    }

    function testRegisterApp_RevertWhen_CallerIsNotWallet() public {
        string memory name = "app";
        address parentContract = address(123);
        uint256[4] memory appLimits = [uint256(0), uint256(0), uint256(0), uint256(0)];
        address[] memory appContracts = new address[](0);

        // register app
        vm.expectRevert();
        vm.prank(address(_user));
        _kintoAppRegistry.registerApp(name, parentContract, appContracts, appLimits, new address[](0));
    }

    function testUpdateMetadata() public {
        string memory name = "app";
        address parentContract = address(123);

        approveKYC(_kycProvider, _user, _userPk);

        address[] memory appContracts = new address[](1);
        appContracts[0] = address(8);

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = _kintoAppRegistry.RATE_LIMIT_PERIOD();
        appLimits[1] = _kintoAppRegistry.RATE_LIMIT_THRESHOLD();
        appLimits[2] = _kintoAppRegistry.GAS_LIMIT_PERIOD();
        appLimits[3] = _kintoAppRegistry.GAS_LIMIT_THRESHOLD();

        // register app
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(
            name,
            parentContract,
            appContracts,
            [appLimits[0], appLimits[1], appLimits[2], appLimits[3]],
            new address[](0)
        );

        // update app
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.updateMetadata(
            "test2", parentContract, appContracts, [uint256(1), uint256(1), uint256(1), uint256(1)], new address[](0)
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

    function testRegisterApp_RevertWithSameChildDoesNotOverrideChildToParent() public {
        string memory name = "app";
        address parentContract = address(123);

        approveKYC(_kycProvider, _user, _userPk);

        address[] memory appContracts = new address[](1);
        appContracts[0] = address(8);

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = _kintoAppRegistry.RATE_LIMIT_PERIOD();
        appLimits[1] = _kintoAppRegistry.RATE_LIMIT_THRESHOLD();
        appLimits[2] = _kintoAppRegistry.GAS_LIMIT_PERIOD();
        appLimits[3] = _kintoAppRegistry.GAS_LIMIT_THRESHOLD();

        // register app
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(
            name,
            parentContract,
            appContracts,
            [appLimits[0], appLimits[1], appLimits[2], appLimits[3]],
            new address[](0)
        );

        vm.prank(address(_kintoWallet));
        vm.expectRevert(IKintoAppRegistry.ChildAlreadyRegistered.selector);
        _kintoAppRegistry.registerApp(
            "test 5",
            address(2),
            appContracts,
            [appLimits[0], appLimits[1], appLimits[2], appLimits[3]],
            new address[](0)
        );
    }

    function testUpdateMetadata_RevertWhen_CallerIsNotDeveloper() public {
        vm.prank(address(_kintoWallet));
        registerApp(address(_kintoWallet), "app", address(0), new address[](0));

        // update app
        vm.prank(_user);
        vm.expectRevert(IKintoAppRegistry.OnlyAppDeveloper.selector);
        _kintoAppRegistry.updateMetadata(
            "app", address(0), new address[](0), [uint256(1), uint256(1), uint256(1), uint256(1)], new address[](0)
        );
    }

    /* ============ DSA ============ */

    function testEnableDSA_WhenCallerIsOwner() public {
        registerApp(address(_kintoWallet), "app", address(_engenCredits), new address[](0));
        vm.prank(_owner);
        _kintoAppRegistry.enableDSA(address(_engenCredits));

        IKintoAppRegistry.Metadata memory metadata = _kintoAppRegistry.getAppMetadata(address(_engenCredits));
        assertEq(metadata.dsaEnabled, true);
    }

    function testEnableDSA_RevertWhen_CallerIsNotOwner() public {
        registerApp(address(_kintoWallet), "app", address(_engenCredits), new address[](0));

        vm.expectRevert("Ownable: caller is not the owner");
        _kintoAppRegistry.enableDSA(address(_engenCredits));
    }

    function testEnableDSA_RevertWhen_AlreadyEnabled() public {
        registerApp(address(_kintoWallet), "app", address(_engenCredits), new address[](0));
        vm.prank(_owner);
        _kintoAppRegistry.enableDSA(address(_engenCredits));

        vm.prank(_owner);
        vm.expectRevert(IKintoAppRegistry.DSAAlreadyEnabled.selector);
        _kintoAppRegistry.enableDSA(address(_engenCredits));
    }

    /* ============ Sponsored Contracts ============ */

    function testSetSponsoredContracts() public {
        registerApp(address(_kintoWallet), "app", address(_engenCredits), new address[](0));

        address[] memory contracts = new address[](2);
        contracts[0] = address(8);
        contracts[1] = address(9);

        bool[] memory flags = new bool[](2);
        flags[0] = false;
        flags[1] = true;

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.setSponsoredContracts(address(_engenCredits), contracts, flags);

        assertEq(_kintoAppRegistry.isSponsored(address(_engenCredits), address(8)), false);
        assertEq(_kintoAppRegistry.isSponsored(address(_engenCredits), address(9)), true);
        assertEq(_kintoAppRegistry.isSponsored(address(_engenCredits), address(10)), false);
    }

    function testSetSponsoredContracts_RevertWhen_CallerIsNotCreator() public {
        registerApp(address(_kintoWallet), "app", address(_engenCredits), new address[](0));

        address[] memory contracts = new address[](2);
        contracts[0] = address(8);
        contracts[1] = address(9);

        bool[] memory flags = new bool[](2);
        flags[0] = false;
        flags[1] = true;

        vm.prank(_user);
        vm.expectRevert(IKintoAppRegistry.InvalidSponsorSetter.selector);
        _kintoAppRegistry.setSponsoredContracts(address(_engenCredits), contracts, flags);
    }

    function testSetSponsoredContracts_RevertWhen_LengthMismatch() public {
        registerApp(address(_kintoWallet), "app", address(_engenCredits), new address[](0));

        address[] memory contracts = new address[](1);
        contracts[0] = address(8);

        bool[] memory flags = new bool[](2);
        flags[0] = false;
        flags[1] = true;

        vm.expectRevert(IKintoAppRegistry.LengthMismatch.selector);
        _kintoAppRegistry.setSponsoredContracts(address(_engenCredits), contracts, flags);
    }

    /* ============ Transfer ============ */

    function test_RevertWhen_TransfersAreDisabled() public {
        approveKYC(_kycProvider, _user, _userPk);

        address parentContract = address(_engenCredits);

        address[] memory appContracts = new address[](1);
        appContracts[0] = address(8);

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = _kintoAppRegistry.RATE_LIMIT_PERIOD();
        appLimits[1] = _kintoAppRegistry.RATE_LIMIT_THRESHOLD();
        appLimits[2] = _kintoAppRegistry.GAS_LIMIT_PERIOD();
        appLimits[3] = _kintoAppRegistry.GAS_LIMIT_THRESHOLD();

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(
            "", parentContract, appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]], new address[](0)
        );

        uint256 tokenIdx = _kintoAppRegistry.tokenOfOwnerByIndex(address(_kintoWallet), 0);
        vm.expectRevert(IKintoAppRegistry.OnlyMintingAllowed.selector);
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.safeTransferFrom(address(_kintoWallet), _user2, tokenIdx);
    }

    /* ============ Supports Interface ============ */

    function testSupportsInterface() public view {
        bytes4 InterfaceERC721Upgradeable = bytes4(keccak256("balanceOf(address)"))
            ^ bytes4(keccak256("ownerOf(uint256)")) ^ bytes4(keccak256("safeTransferFrom(address,address,uint256,bytes)"))
            ^ bytes4(keccak256("safeTransferFrom(address,address,uint256)"))
            ^ bytes4(keccak256("transferFrom(address,address,uint256)")) ^ bytes4(keccak256("approve(address,uint256)"))
            ^ bytes4(keccak256("setApprovalForAll(address,bool)")) ^ bytes4(keccak256("getApproved(uint256)"))
            ^ bytes4(keccak256("isApprovedForAll(address,address)"));

        assertTrue(_kintoID.supportsInterface(InterfaceERC721Upgradeable));
    }

    /* ============ updateSystemContracts ============ */

    function getSystemContracts() public view returns (address[] memory) {
        uint256 count = 0;
        address[] memory tempArray = new address[](100); // Arbitrary large size

        for (uint256 i = 0; i < 100; i++) {
            try _kintoAppRegistry.systemContracts(i) returns (address addr) {
                tempArray[count] = addr;
                count++;
            } catch {
                break;
            }
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = tempArray[i];
        }

        return result;
    }

    function testUpdateSystemContracts() public {
        // Initial empty system contracts array
        address[] memory initialSystemContracts = getSystemContracts();
        assertEq(initialSystemContracts.length, 0);

        // Update system contracts array
        address[] memory newSystemContracts = new address[](2);
        newSystemContracts[0] = address(1);
        newSystemContracts[1] = address(2);

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemContracts(newSystemContracts);

        // Verify the system contracts array is updated
        address[] memory updatedSystemContracts = getSystemContracts();
        assertEq(updatedSystemContracts.length, newSystemContracts.length);
        assertEq(updatedSystemContracts[0], newSystemContracts[0]);
        assertEq(updatedSystemContracts[1], newSystemContracts[1]);
    }

    function testUpdateSystemContractsWithDifferentLength() public {
        // Initial update with 2 contracts
        address[] memory initialContracts = new address[](2);
        initialContracts[0] = address(1);
        initialContracts[1] = address(2);

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemContracts(initialContracts);

        // Verify initial update
        address[] memory updatedContracts = getSystemContracts();
        assertEq(updatedContracts.length, 2);
        assertEq(updatedContracts[0], address(1));
        assertEq(updatedContracts[1], address(2));

        // Update with 3 contracts (increasing length)
        address[] memory newContracts = new address[](3);
        newContracts[0] = address(3);
        newContracts[1] = address(4);
        newContracts[2] = address(5);

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemContracts(newContracts);

        // Verify update with increased length
        updatedContracts = getSystemContracts();
        assertEq(updatedContracts.length, 3);
        assertEq(updatedContracts[0], address(3));
        assertEq(updatedContracts[1], address(4));
        assertEq(updatedContracts[2], address(5));

        // Update with 1 contract (decreasing length)
        address[] memory finalContracts = new address[](1);
        finalContracts[0] = address(6);

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemContracts(finalContracts);

        // Verify update with decreased length
        updatedContracts = getSystemContracts();
        assertEq(updatedContracts.length, 1);
        assertEq(updatedContracts[0], address(6));
    }

    function testUpdateSystemContracts_RevertWhen_CallerIsNotOwner() public {
        address[] memory newSystemContracts = new address[](2);
        newSystemContracts[0] = address(1);
        newSystemContracts[1] = address(2);

        vm.prank(_user);
        vm.expectRevert("Ownable: caller is not the owner");
        _kintoAppRegistry.updateSystemContracts(newSystemContracts);
    }

    /* ============ isContractCallAllowedFromEOA ============ */

    function testIsContractCallAllowedFromEOA_WhenSystemContract() public {
        // Update system contracts array
        address[] memory newSystemContracts = new address[](2);
        newSystemContracts[0] = address(1);
        newSystemContracts[1] = address(2);

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemContracts(newSystemContracts);

        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, address(1)), true);
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, address(2)), true);
    }

    function testIsContractCallAllowedFromEOA_WhenRandomEOACreate2() public view {
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user2, address(CREATE2)), false);
    }

    function testIsContractCallAllowedFromEOA_WhenRandomEOACreate() public view {
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user2, address(0)), false);
    }

    function testIsContractCallAllowedFromEOA_WhenRandomEOA() public view {
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user2, address(0xdead)), false);
    }

    function testIsContractCallAllowedFromEOA_WhenCreate2() public {
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.setDeployerEOA(address(_kintoWallet), address(0xde));

        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(address(0xde), address(CREATE2)), true);
    }

    function testIsContractCallAllowedFromEOA_WhenCreate() public {
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.setDeployerEOA(address(_kintoWallet), address(0xde));

        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(address(0xde), address(0)), true);
    }

    function testIsContractCallAllowedFromEOA_WhenDevEOA() public {
        address[] memory appContracts = new address[](2);
        appContracts[0] = address(11);
        appContracts[1] = address(22);

        address[] memory devEOAs = new address[](3);
        devEOAs[0] = _owner;
        devEOAs[1] = _user;
        devEOAs[2] = _user2;

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = _kintoAppRegistry.RATE_LIMIT_PERIOD();
        appLimits[1] = _kintoAppRegistry.RATE_LIMIT_THRESHOLD();
        appLimits[2] = _kintoAppRegistry.GAS_LIMIT_PERIOD();
        appLimits[3] = _kintoAppRegistry.GAS_LIMIT_THRESHOLD();

        resetSigners(devEOAs, 1);

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(
            "test", address(99), appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]], devEOAs
        );

        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_owner, address(11)), true);
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user, address(11)), true);
        assertEq(_kintoAppRegistry.isContractCallAllowedFromEOA(_user2, address(22)), true);
    }

    /* ============ setDeployerEOA ============ */

    function testSetDeployerEOA() public {
        vm.prank(address(_kintoWallet));
        vm.expectEmit(true, true, true, true);
        emit IKintoAppRegistry.DeployerSet(address(0xde));
        _kintoAppRegistry.setDeployerEOA(address(_kintoWallet), address(0xde));

        assertEq(_kintoAppRegistry.deployerToWallet(address(0xde)), address(_kintoWallet));
    }
}

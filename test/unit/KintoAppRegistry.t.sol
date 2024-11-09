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

    constructor(IKintoWalletFactory _walletFactory, SponsorPaymaster _paymaster)
        KintoAppRegistry(_walletFactory, _paymaster)
    {}
}

contract KintoAppRegistryTest is SharedSetup {
    address internal constant CREATE2 = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    address internal appContract0 = makeAddr("appContract0");
    address internal sponsorContract0 = makeAddr("sponsorContract0");
    address internal sponsorContract1 = makeAddr("sponsorContract1");
    address public constant ENTRYPOINT_V6 = 0x2843C269D2a64eCfA63548E8B3Fc0FD23B7F70cb;
    address public constant ENTRYPOINT_V7 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    address public constant ARB_RETRAYABLE_TX = 0x000000000000000000000000000000000000006E;

    function setUp() public virtual override {
        super.setUp();

        mockContractBytecode(appContract0);
        mockContractBytecode(sponsorContract0);
        mockContractBytecode(sponsorContract1);
    }

    function testUp() public override {
        super.testUp();
        useHarness();

        assertEq(_kintoAppRegistry.owner(), _owner);
        assertEq(_kintoAppRegistry.name(), "Kinto APP");
        assertEq(_kintoAppRegistry.symbol(), "KINTOAPP");
        assertEq(
            KintoAppRegistryHarness(address(_kintoAppRegistry)).exposed_baseURI(),
            "https://kinto.xyz/metadata/kintoapp/"
        );

        address[] memory systemContracts = _kintoAppRegistry.getSystemContracts();
        assertEq(systemContracts[0], address(_kintoAppRegistry));
        assertEq(systemContracts[1], address(ENTRYPOINT_V6));
        assertEq(systemContracts[2], address(ENTRYPOINT_V7));
        assertEq(systemContracts[3], address(ARB_RETRAYABLE_TX));
        assertEq(systemContracts[4], address(_paymaster));
    }

    /* ============ Upgrade ============ */

    function testUpgradeTo() public {
        vm.startPrank(_owner);

        KintoAppRegistryV2 _implementationV2 = new KintoAppRegistryV2(_walletFactory, _paymaster);
        _kintoAppRegistry.upgradeTo(address(_implementationV2));
        assertEq(KintoAppRegistryV2(address(_kintoAppRegistry)).newFunction(), 1);

        vm.stopPrank();
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner() public {
        KintoAppRegistryV2 _implementationV2 = new KintoAppRegistryV2(_walletFactory, _paymaster);
        vm.expectRevert("Ownable: caller is not the owner");
        _kintoAppRegistry.upgradeTo(address(_implementationV2));
    }

    /* ============ RegisterApp & UpdateApp ============ */

    function testRegisterApp() public {
        string memory name = "app";
        address parentContract = address(123);

        approveKYC(_kycProvider, _user, _userPk);

        address[] memory appContracts = new address[](1);
        appContracts[0] = appContract0;

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = RATE_LIMIT_PERIOD;
        appLimits[1] = RATE_LIMIT_THRESHOLD;
        appLimits[2] = GAS_LIMIT_PERIOD;
        appLimits[3] = GAS_LIMIT_THRESHOLD;

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
        assertEq(_kintoAppRegistry.isSponsored(parentContract, appContract0), true);
        assertEq(_kintoAppRegistry.getApp(appContract0), parentContract);
        assertEq(metadata.devEOAs[0], eoas[0]);

        // check child limits
        uint256[4] memory limits = _kintoAppRegistry.getContractLimits(appContract0);
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
        metadata = _kintoAppRegistry.getAppMetadata(appContract0);
        assertEq(metadata.name, name);
    }

    function testRegisterApp_RevertWhen_ChildrenIsWallet() public {
        approveKYC(_kycProvider, _user, _userPk);

        uint256[4] memory appLimits = [uint256(0), uint256(0), uint256(0), uint256(0)];
        address[] memory appContracts = new address[](1);
        appContracts[0] = address(_kintoWallet);

        // register app
        vm.expectRevert(abi.encodeWithSelector(IKintoAppRegistry.CannotRegisterWallet.selector, _kintoWallet));
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
        vm.expectRevert(abi.encodeWithSelector(IKintoAppRegistry.AlreadyRegistered.selector, parentContract));
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(name, parentContract, appContracts, appLimits, new address[](0));
    }

    function testRegisterApp_RevertWhen_ParentIsChild() public {
        // register app with child address 2
        string memory name = "app";
        address parentContract = address(_engenCredits);
        uint256[4] memory appLimits = [uint256(0), uint256(0), uint256(0), uint256(0)];
        address[] memory appContracts = new address[](1);
        appContracts[0] = appContract0;

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(name, parentContract, appContracts, appLimits, new address[](0));

        // registering app "app2" with parent address 2 should revert
        appContracts = new address[](0);
        vm.expectRevert(abi.encodeWithSelector(IKintoAppRegistry.ParentAlreadyChild.selector, appContract0));
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(name, appContract0, appContracts, appLimits, new address[](0));
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
        appContracts[0] = appContract0;

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = RATE_LIMIT_PERIOD;
        appLimits[1] = RATE_LIMIT_THRESHOLD;
        appLimits[2] = GAS_LIMIT_PERIOD;
        appLimits[3] = GAS_LIMIT_THRESHOLD;

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
        assertEq(_kintoAppRegistry.isSponsored(parentContract, appContract0), true);
    }

    function testRemoveOldDevEOAs() public {
        address parentContract = address(0x123);
        address[] memory initialDevEOAs = new address[](3);
        initialDevEOAs[0] = address(0xdead);
        initialDevEOAs[1] = address(0xbeef);
        initialDevEOAs[2] = address(0xcafe);

        address[] memory newDevEOAs = new address[](2);
        newDevEOAs[0] = address(0x1234);
        newDevEOAs[1] = address(0x5678);

        // Set up initial state
        approveKYC(_kycProvider, _user, _userPk);
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(
            "Test App",
            parentContract,
            new address[](0),
            [uint256(0), uint256(0), uint256(0), uint256(0)],
            initialDevEOAs
        );

        // Verify initial state
        for (uint256 i = 0; i < initialDevEOAs.length; i++) {
            assertEq(_kintoAppRegistry.devEoaToApp(initialDevEOAs[i]), parentContract);
        }

        // Update metadata with new dev EOAs
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.updateMetadata(
            "Updated Test App",
            parentContract,
            new address[](0),
            [uint256(0), uint256(0), uint256(0), uint256(0)],
            newDevEOAs
        );

        // Verify old dev EOAs are removed
        for (uint256 i = 0; i < initialDevEOAs.length; i++) {
            assertEq(_kintoAppRegistry.devEoaToApp(initialDevEOAs[i]), address(0));
        }

        // Verify new dev EOAs are set
        for (uint256 i = 0; i < newDevEOAs.length; i++) {
            assertEq(_kintoAppRegistry.devEoaToApp(newDevEOAs[i]), parentContract);
        }

        // Verify app metadata is updated
        IKintoAppRegistry.Metadata memory updatedMetadata = _kintoAppRegistry.getAppMetadata(parentContract);
        assertEq(updatedMetadata.name, "Updated Test App");
        assertEq(updatedMetadata.devEOAs.length, newDevEOAs.length);
        for (uint256 i = 0; i < newDevEOAs.length; i++) {
            assertEq(updatedMetadata.devEOAs[i], newDevEOAs[i]);
        }
    }

    function testRegisterApp_RevertWhenAppContractIsParentContact() public {
        string memory name = "app";
        approveKYC(_kycProvider, _user, _userPk);

        address[] memory appContracts = new address[](1);
        appContracts[0] = appContract0;

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = RATE_LIMIT_PERIOD;
        appLimits[1] = RATE_LIMIT_THRESHOLD;
        appLimits[2] = GAS_LIMIT_PERIOD;
        appLimits[3] = GAS_LIMIT_THRESHOLD;

        vm.prank(address(_kintoWallet));
        vm.expectRevert(abi.encodeWithSelector(IKintoAppRegistry.ContractAlreadyRegistered.selector, appContract0));
        _kintoAppRegistry.registerApp(
            name, appContract0, appContracts, [appLimits[0], appLimits[1], appLimits[2], appLimits[3]], new address[](0)
        );
    }

    function testRegisterApp_RevertWithSameChildDoesNotOverrideChildToParent() public {
        string memory name = "app";
        address parentContract = address(123);

        approveKYC(_kycProvider, _user, _userPk);

        address[] memory appContracts = new address[](1);
        appContracts[0] = appContract0;

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = RATE_LIMIT_PERIOD;
        appLimits[1] = RATE_LIMIT_THRESHOLD;
        appLimits[2] = GAS_LIMIT_PERIOD;
        appLimits[3] = GAS_LIMIT_THRESHOLD;

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
        vm.expectRevert(abi.encodeWithSelector(IKintoAppRegistry.ContractAlreadyRegistered.selector, appContract0));
        _kintoAppRegistry.registerApp(
            "test 5",
            address(2),
            appContracts,
            [appLimits[0], appLimits[1], appLimits[2], appLimits[3]],
            new address[](0)
        );
    }

    function testUpdateMetadata_RevertWhen_CallerIsNotDeveloper() public {
        registerApp(address(_kintoWallet), "app", address(0), new address[](0));

        // update app
        vm.prank(_user);
        vm.expectRevert(
            abi.encodeWithSelector(IKintoAppRegistry.OnlyAppDeveloper.selector, _user, address(_kintoWallet))
        );
        _kintoAppRegistry.updateMetadata(
            "app", address(0), new address[](0), [uint256(1), uint256(1), uint256(1), uint256(1)], new address[](0)
        );
    }

    function testRegisterApp_RevertWhen_ContractHasNoBytecode() public {
        string memory name = "app";
        address parentContract = address(123);

        approveKYC(_kycProvider, _user, _userPk);

        address[] memory appContracts = new address[](1);
        appContracts[0] = address(0x1234); // An address without bytecode

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = RATE_LIMIT_PERIOD;
        appLimits[1] = RATE_LIMIT_THRESHOLD;
        appLimits[2] = GAS_LIMIT_PERIOD;
        appLimits[3] = GAS_LIMIT_THRESHOLD;

        vm.prank(address(_kintoWallet));
        vm.expectRevert(abi.encodeWithSelector(IKintoAppRegistry.ContractHasNoBytecode.selector, address(0x1234)));
        _kintoAppRegistry.registerApp(
            name,
            parentContract,
            appContracts,
            [appLimits[0], appLimits[1], appLimits[2], appLimits[3]],
            new address[](0)
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
        vm.expectRevert(abi.encodeWithSelector(IKintoAppRegistry.DSAAlreadyEnabled.selector, address(_engenCredits)));
        _kintoAppRegistry.enableDSA(address(_engenCredits));
    }

    /* ============ Sponsored Contracts ============ */

    function testSetSponsoredContracts() public {
        registerApp(address(_kintoWallet), "app", address(_engenCredits), new address[](0));

        address[] memory contracts = new address[](2);
        contracts[0] = sponsorContract0;
        contracts[1] = sponsorContract1;

        bool[] memory flags = new bool[](2);
        flags[0] = false;
        flags[1] = true;

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.setSponsoredContracts(address(_engenCredits), contracts, flags);

        assertEq(_kintoAppRegistry.isSponsored(address(_engenCredits), sponsorContract0), false);
        assertEq(_kintoAppRegistry.isSponsored(address(_engenCredits), sponsorContract1), true);
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
        vm.expectRevert(
            abi.encodeWithSelector(IKintoAppRegistry.InvalidSponsorSetter.selector, _user, address(_kintoWallet))
        );
        _kintoAppRegistry.setSponsoredContracts(address(_engenCredits), contracts, flags);
    }

    function testSetSponsoredContracts_RevertWhen_LengthMismatch() public {
        registerApp(address(_kintoWallet), "app", address(_engenCredits), new address[](0));

        address[] memory contracts = new address[](1);
        contracts[0] = address(8);

        bool[] memory flags = new bool[](2);
        flags[0] = false;
        flags[1] = true;

        vm.expectRevert(abi.encodeWithSelector(IKintoAppRegistry.LengthMismatch.selector, 1, 2));
        _kintoAppRegistry.setSponsoredContracts(address(_engenCredits), contracts, flags);
    }

    /* ============ Transfer ============ */

    function test_RevertWhen_TransfersAreDisabled() public {
        approveKYC(_kycProvider, _user, _userPk);

        address parentContract = address(_engenCredits);

        address[] memory appContracts = new address[](1);
        appContracts[0] = appContract0;

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = RATE_LIMIT_PERIOD;
        appLimits[1] = RATE_LIMIT_THRESHOLD;
        appLimits[2] = GAS_LIMIT_PERIOD;
        appLimits[3] = GAS_LIMIT_THRESHOLD;

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

    function testUpdateSystemContracts() public {
        // Initial empty system contracts array
        address[] memory initialSystemContracts = _kintoAppRegistry.getSystemContracts();
        assertEq(initialSystemContracts.length, 9);

        // Update system contracts array
        address[] memory newSystemContracts = new address[](2);
        newSystemContracts[0] = address(1);
        newSystemContracts[1] = address(2);

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemContracts(newSystemContracts);

        // Verify the system contracts array is updated
        address[] memory updatedSystemContracts = _kintoAppRegistry.getSystemContracts();
        assertEq(updatedSystemContracts.length, newSystemContracts.length + 5);
        assertEq(updatedSystemContracts[5], newSystemContracts[0]);
        assertEq(updatedSystemContracts[6], newSystemContracts[1]);
    }

    function testUpdateSystemContractsWithDifferentLength() public {
        // Initial update with 2 contracts
        address[] memory initialContracts = new address[](2);
        initialContracts[0] = address(1);
        initialContracts[1] = address(2);

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemContracts(initialContracts);

        // Verify initial update
        address[] memory updatedContracts = _kintoAppRegistry.getSystemContracts();
        assertEq(updatedContracts.length, 7);
        assertEq(updatedContracts[5], address(1));
        assertEq(updatedContracts[6], address(2));

        // Update with 3 contracts (increasing length)
        address[] memory newContracts = new address[](3);
        newContracts[0] = address(3);
        newContracts[1] = address(4);
        newContracts[2] = address(5);

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemContracts(newContracts);

        // Verify update with increased length
        updatedContracts = _kintoAppRegistry.getSystemContracts();
        assertEq(updatedContracts.length, 8);
        assertEq(updatedContracts[5], address(3));
        assertEq(updatedContracts[6], address(4));
        assertEq(updatedContracts[7], address(5));

        // Update with 1 contract (decreasing length)
        address[] memory finalContracts = new address[](1);
        finalContracts[0] = address(6);

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemContracts(finalContracts);

        // Verify update with decreased length
        updatedContracts = _kintoAppRegistry.getSystemContracts();
        assertEq(updatedContracts.length, 6);
        assertEq(updatedContracts[5], address(6));
    }

    function testUpdateSystemContracts_RevertWhen_CallerIsNotOwner() public {
        address[] memory newSystemContracts = new address[](2);
        newSystemContracts[0] = address(1);
        newSystemContracts[1] = address(2);

        vm.prank(_user);
        vm.expectRevert("Ownable: caller is not the owner");
        _kintoAppRegistry.updateSystemContracts(newSystemContracts);
    }

    /* ============ updateSystemApps ============ */

    function testUpdateSystemApps() public {
        // Initial empty system apps array
        address[] memory initialSystemApps = _kintoAppRegistry.getSystemApps();
        assertEq(initialSystemApps.length, 0);

        // Update system apps array
        address[] memory newSystemApps = new address[](2);
        newSystemApps[0] = address(1);
        newSystemApps[1] = address(2);

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemApps(newSystemApps);

        // Verify the system apps array is updated
        address[] memory updatedSystemApps = _kintoAppRegistry.getSystemApps();
        assertEq(updatedSystemApps.length, newSystemApps.length);
        assertEq(updatedSystemApps[0], newSystemApps[0]);
        assertEq(updatedSystemApps[1], newSystemApps[1]);

        // Check isSystemApp mapping
        assertTrue(_kintoWallet.isAppApproved(address(1)));
        assertTrue(_kintoAppRegistry.isSystemApp(address(1)));
        assertTrue(_kintoAppRegistry.isSystemApp(address(2)));
        assertFalse(_kintoAppRegistry.isSystemApp(address(3)));
    }

    function testUpdateSystemAppsWithDifferentLength() public {
        // Initial update with 2 apps
        address[] memory initialApps = new address[](2);
        initialApps[0] = address(1);
        initialApps[1] = address(2);

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemApps(initialApps);

        // Verify initial update
        address[] memory updatedApps = _kintoAppRegistry.getSystemApps();
        assertEq(updatedApps.length, 2);
        assertEq(updatedApps[0], address(1));
        assertEq(updatedApps[1], address(2));

        // Update with 3 apps (increasing length)
        address[] memory newApps = new address[](3);
        newApps[0] = address(3);
        newApps[1] = address(4);
        newApps[2] = address(5);

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemApps(newApps);

        // Verify update with increased length
        updatedApps = _kintoAppRegistry.getSystemApps();
        assertEq(updatedApps.length, 3);
        assertEq(updatedApps[0], address(3));
        assertEq(updatedApps[1], address(4));
        assertEq(updatedApps[2], address(5));

        // Check isSystemApp mapping
        assertFalse(_kintoAppRegistry.isSystemApp(address(1)));
        assertFalse(_kintoAppRegistry.isSystemApp(address(2)));
        assertTrue(_kintoAppRegistry.isSystemApp(address(3)));
        assertTrue(_kintoAppRegistry.isSystemApp(address(4)));
        assertTrue(_kintoAppRegistry.isSystemApp(address(5)));

        // Update with 1 app (decreasing length)
        address[] memory finalApps = new address[](1);
        finalApps[0] = address(6);

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemApps(finalApps);

        // Verify update with decreased length
        updatedApps = _kintoAppRegistry.getSystemApps();
        assertEq(updatedApps.length, 1);
        assertEq(updatedApps[0], address(6));

        // Check isSystemApp mapping
        assertFalse(_kintoAppRegistry.isSystemApp(address(3)));
        assertFalse(_kintoAppRegistry.isSystemApp(address(4)));
        assertFalse(_kintoAppRegistry.isSystemApp(address(5)));
        assertTrue(_kintoAppRegistry.isSystemApp(address(6)));
    }

    function testUpdateSystemApps_RevertWhen_CallerIsNotOwner() public {
        address[] memory newSystemApps = new address[](2);
        newSystemApps[0] = address(1);
        newSystemApps[1] = address(2);

        vm.prank(_user);
        vm.expectRevert("Ownable: caller is not the owner");
        _kintoAppRegistry.updateSystemApps(newSystemApps);
    }

    function testUpdateSystemApps_CorrectlyUpdatesIsSystemAppMapping() public {
        // Initial update
        address[] memory initialApps = new address[](2);
        initialApps[0] = address(1);
        initialApps[1] = address(2);

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemApps(initialApps);

        // Verify initial mapping
        assertTrue(_kintoAppRegistry.isSystemApp(address(1)));
        assertTrue(_kintoAppRegistry.isSystemApp(address(2)));
        assertFalse(_kintoAppRegistry.isSystemApp(address(3)));

        // Update with new apps
        address[] memory newApps = new address[](2);
        newApps[0] = address(2); // Keep one existing app
        newApps[1] = address(3); // Add a new app

        vm.prank(_owner);
        _kintoAppRegistry.updateSystemApps(newApps);

        // Verify updated mapping
        assertFalse(_kintoAppRegistry.isSystemApp(address(1))); // Should be removed
        assertTrue(_kintoAppRegistry.isSystemApp(address(2))); // Should still be true
        assertTrue(_kintoAppRegistry.isSystemApp(address(3))); // Should be added
        assertFalse(_kintoAppRegistry.isSystemApp(address(4))); // Random address should be false
    }

    /* ============ updateReservedContracts ============ */

    function testUpdateReservedContracts() public {
        // Initial empty reserved contracts array
        address[] memory initialReservedContracts = _kintoAppRegistry.getReservedContracts();
        assertEq(initialReservedContracts.length, 0);

        // Update reserved contracts array
        address[] memory newReservedContracts = new address[](2);
        newReservedContracts[0] = address(1);
        newReservedContracts[1] = address(2);

        vm.prank(_owner);
        _kintoAppRegistry.updateReservedContracts(newReservedContracts);

        // Verify the reserved contracts array is updated
        address[] memory updatedReservedContracts = _kintoAppRegistry.getReservedContracts();
        assertEq(updatedReservedContracts.length, newReservedContracts.length);
        assertEq(updatedReservedContracts[0], newReservedContracts[0]);
        assertEq(updatedReservedContracts[1], newReservedContracts[1]);

        // Check isReservedContract mapping
        assertTrue(_kintoAppRegistry.isReservedContract(address(1)));
        assertTrue(_kintoAppRegistry.isReservedContract(address(2)));
        assertFalse(_kintoAppRegistry.isReservedContract(address(3)));
    }

    function testUpdateReservedContractsWithDifferentLength() public {
        // Initial update with 2 contracts
        address[] memory initialContracts = new address[](2);
        initialContracts[0] = address(1);
        initialContracts[1] = address(2);

        vm.prank(_owner);
        _kintoAppRegistry.updateReservedContracts(initialContracts);

        // Verify initial update
        address[] memory updatedContracts = _kintoAppRegistry.getReservedContracts();
        assertEq(updatedContracts.length, 2);
        assertEq(updatedContracts[0], address(1));
        assertEq(updatedContracts[1], address(2));

        // Update with 3 contracts (increasing length)
        address[] memory newContracts = new address[](3);
        newContracts[0] = address(3);
        newContracts[1] = address(4);
        newContracts[2] = address(5);

        vm.prank(_owner);
        _kintoAppRegistry.updateReservedContracts(newContracts);

        // Verify update with increased length
        updatedContracts = _kintoAppRegistry.getReservedContracts();
        assertEq(updatedContracts.length, 3);
        assertEq(updatedContracts[0], address(3));
        assertEq(updatedContracts[1], address(4));
        assertEq(updatedContracts[2], address(5));

        // Check isReservedContract mapping
        assertFalse(_kintoAppRegistry.isReservedContract(address(1)));
        assertFalse(_kintoAppRegistry.isReservedContract(address(2)));
        assertTrue(_kintoAppRegistry.isReservedContract(address(3)));
        assertTrue(_kintoAppRegistry.isReservedContract(address(4)));
        assertTrue(_kintoAppRegistry.isReservedContract(address(5)));

        // Update with 1 contract (decreasing length)
        address[] memory finalContracts = new address[](1);
        finalContracts[0] = address(6);

        vm.prank(_owner);
        _kintoAppRegistry.updateReservedContracts(finalContracts);

        // Verify update with decreased length
        updatedContracts = _kintoAppRegistry.getReservedContracts();
        assertEq(updatedContracts.length, 1);
        assertEq(updatedContracts[0], address(6));

        // Check isReservedContract mapping
        assertFalse(_kintoAppRegistry.isReservedContract(address(3)));
        assertFalse(_kintoAppRegistry.isReservedContract(address(4)));
        assertFalse(_kintoAppRegistry.isReservedContract(address(5)));
        assertTrue(_kintoAppRegistry.isReservedContract(address(6)));
    }

    function testUpdateReservedContracts_RevertWhen_CallerIsNotOwner() public {
        address[] memory newReservedContracts = new address[](2);
        newReservedContracts[0] = address(1);
        newReservedContracts[1] = address(2);

        vm.prank(_user);
        vm.expectRevert("Ownable: caller is not the owner");
        _kintoAppRegistry.updateReservedContracts(newReservedContracts);
    }

    function testRegisterApp_RevertWhen_ContractIsReserved() public {
        // First, set up a reserved contract
        address[] memory newReservedContracts = new address[](1);
        newReservedContracts[0] = address(0x1234);

        vm.prank(_owner);
        _kintoAppRegistry.updateReservedContracts(newReservedContracts);

        // Now try to register an app with the reserved contract as a child
        string memory name = "app";
        address parentContract = address(123);

        approveKYC(_kycProvider, _user, _userPk);

        address[] memory appContracts = new address[](1);
        appContracts[0] = address(0x1234); // This is the reserved contract

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = RATE_LIMIT_PERIOD;
        appLimits[1] = RATE_LIMIT_THRESHOLD;
        appLimits[2] = GAS_LIMIT_PERIOD;
        appLimits[3] = GAS_LIMIT_THRESHOLD;

        vm.prank(address(_kintoWallet));
        vm.expectRevert(abi.encodeWithSelector(IKintoAppRegistry.ReservedContract.selector, address(0x1234)));
        _kintoAppRegistry.registerApp(
            name,
            parentContract,
            appContracts,
            [appLimits[0], appLimits[1], appLimits[2], appLimits[3]],
            new address[](0)
        );
    }

    function testUpdateMetadata_RevertWhen_ContractIsReserved() public {
        // First, register an app
        string memory name = "app";
        address parentContract = address(123);

        approveKYC(_kycProvider, _user, _userPk);

        address[] memory appContracts = new address[](1);
        appContracts[0] = appContract0;

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = RATE_LIMIT_PERIOD;
        appLimits[1] = RATE_LIMIT_THRESHOLD;
        appLimits[2] = GAS_LIMIT_PERIOD;
        appLimits[3] = GAS_LIMIT_THRESHOLD;

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(
            name,
            parentContract,
            appContracts,
            [appLimits[0], appLimits[1], appLimits[2], appLimits[3]],
            new address[](0)
        );

        // Now set up a reserved contract
        address[] memory newReservedContracts = new address[](1);
        newReservedContracts[0] = address(0x1234);

        vm.prank(_owner);
        _kintoAppRegistry.updateReservedContracts(newReservedContracts);

        // Try to update the app metadata with the reserved contract as a child
        appContracts[0] = address(0x1234); // This is the reserved contract

        vm.prank(address(_kintoWallet));
        vm.expectRevert(abi.encodeWithSelector(IKintoAppRegistry.ReservedContract.selector, address(0x1234)));
        _kintoAppRegistry.updateMetadata(
            name,
            parentContract,
            appContracts,
            [appLimits[0], appLimits[1], appLimits[2], appLimits[3]],
            new address[](0)
        );
    }

    /* ============ setDeployerEOA ============ */

    function testSetDeployerEOA() public {
        vm.prank(address(_kintoWallet));
        vm.expectEmit(true, true, true, true);
        emit IKintoAppRegistry.DeployerSet(address(0xde));
        _kintoAppRegistry.setDeployerEOA(address(_kintoWallet), address(0xde));

        assertEq(_kintoAppRegistry.deployerToWallet(address(0xde)), address(_kintoWallet));
    }

    function testRemoveOldDeployerToWallet() public {
        address wallet = address(_kintoWallet);
        address oldDeployer = address(0xdead);
        address newDeployer = address(0xbeef);

        // Set up initial state
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.setDeployerEOA(wallet, oldDeployer);

        // Verify initial state
        assertEq(_kintoAppRegistry.deployerToWallet(oldDeployer), wallet);
        assertEq(_kintoAppRegistry.walletToDeployer(wallet), oldDeployer);

        // Set new deployer
        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.setDeployerEOA(wallet, newDeployer);

        // Verify new state
        assertEq(_kintoAppRegistry.deployerToWallet(newDeployer), wallet);
        assertEq(_kintoAppRegistry.walletToDeployer(wallet), newDeployer);

        // Verify old deployer mapping is removed
        assertEq(_kintoAppRegistry.deployerToWallet(oldDeployer), address(0));
    }

    /* ============ Add App Contracts ============ */

    function testAddAppContracts() public {
        // First register an app
        address parentContract = address(123);
        address[] memory initialContracts = new address[](1);
        initialContracts[0] = appContract0;

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = RATE_LIMIT_PERIOD;
        appLimits[1] = RATE_LIMIT_THRESHOLD;
        appLimits[2] = GAS_LIMIT_PERIOD;
        appLimits[3] = GAS_LIMIT_THRESHOLD;

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(
            "test",
            parentContract,
            initialContracts,
            [appLimits[0], appLimits[1], appLimits[2], appLimits[3]],
            new address[](0)
        );

        // Create new contracts to add
        address[] memory newContracts = new address[](2);
        newContracts[0] = sponsorContract0;
        newContracts[1] = sponsorContract1;

        // Add new contracts
        vm.prank(address(_kintoWallet));
        vm.expectEmit(true, true, true, true);
        emit IKintoAppRegistry.AppContractsAdded(parentContract, newContracts);
        _kintoAppRegistry.addAppContracts(parentContract, newContracts);

        // Verify the contracts were added correctly
        IKintoAppRegistry.Metadata memory metadata = _kintoAppRegistry.getAppMetadata(parentContract);
        assertEq(metadata.appContracts.length, 3);
        assertEq(metadata.appContracts[0], appContract0);
        assertEq(metadata.appContracts[1], sponsorContract0);
        assertEq(metadata.appContracts[2], sponsorContract1);

        // Verify childToParentContract mappings
        assertEq(_kintoAppRegistry.childToParentContract(appContract0), parentContract);
        assertEq(_kintoAppRegistry.childToParentContract(sponsorContract0), parentContract);
        assertEq(_kintoAppRegistry.childToParentContract(sponsorContract1), parentContract);
    }

    function testAddAppContracts_RevertWhen_NotOwner() public {
        address parentContract = address(123);

        // Register initial app
        address[] memory initialContracts = new address[](1);
        initialContracts[0] = appContract0;

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = RATE_LIMIT_PERIOD;
        appLimits[1] = RATE_LIMIT_THRESHOLD;
        appLimits[2] = GAS_LIMIT_PERIOD;
        appLimits[3] = GAS_LIMIT_THRESHOLD;

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(
            "test",
            parentContract,
            initialContracts,
            [appLimits[0], appLimits[1], appLimits[2], appLimits[3]],
            new address[](0)
        );

        // Try to add contracts from non-owner address
        address[] memory newContracts = new address[](1);
        newContracts[0] = sponsorContract0;

        vm.prank(_user);
        vm.expectRevert(
            abi.encodeWithSelector(IKintoAppRegistry.InvalidAppOwner.selector, _user, address(_kintoWallet))
        );
        _kintoAppRegistry.addAppContracts(parentContract, newContracts);
    }

    function testAddAppContracts_RevertWhen_ContractAlreadyRegistered() public {
        address parentContract = address(123);

        // Register initial app
        address[] memory initialContracts = new address[](1);
        initialContracts[0] = appContract0;

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = RATE_LIMIT_PERIOD;
        appLimits[1] = RATE_LIMIT_THRESHOLD;
        appLimits[2] = GAS_LIMIT_PERIOD;
        appLimits[3] = GAS_LIMIT_THRESHOLD;

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(
            "test",
            parentContract,
            initialContracts,
            [appLimits[0], appLimits[1], appLimits[2], appLimits[3]],
            new address[](0)
        );

        // Try to add a contract that's already registered
        address[] memory newContracts = new address[](1);
        newContracts[0] = appContract0;

        vm.prank(address(_kintoWallet));
        vm.expectRevert(abi.encodeWithSelector(IKintoAppRegistry.ContractAlreadyRegistered.selector, appContract0));
        _kintoAppRegistry.addAppContracts(parentContract, newContracts);
    }

    function testAddAppContracts_RevertWhen_ContractHasNoBytecode() public {
        address parentContract = address(123);

        // Register initial app
        address[] memory initialContracts = new address[](1);
        initialContracts[0] = appContract0;

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = RATE_LIMIT_PERIOD;
        appLimits[1] = RATE_LIMIT_THRESHOLD;
        appLimits[2] = GAS_LIMIT_PERIOD;
        appLimits[3] = GAS_LIMIT_THRESHOLD;

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(
            "test",
            parentContract,
            initialContracts,
            [appLimits[0], appLimits[1], appLimits[2], appLimits[3]],
            new address[](0)
        );

        // Try to add a contract with no bytecode
        address[] memory newContracts = new address[](1);
        address contractWithNoBytecode = address(0x1234);
        newContracts[0] = contractWithNoBytecode;

        vm.prank(address(_kintoWallet));
        vm.expectRevert(
            abi.encodeWithSelector(IKintoAppRegistry.ContractHasNoBytecode.selector, contractWithNoBytecode)
        );
        _kintoAppRegistry.addAppContracts(parentContract, newContracts);
    }

    /* ============ Remove App Contracts ============ */

    function testRemoveAppContracts() public {
        // First register an app with multiple contracts
        address parentContract = address(123);
        address[] memory initialContracts = new address[](3);
        initialContracts[0] = appContract0;
        initialContracts[1] = sponsorContract0;
        initialContracts[2] = sponsorContract1;

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = RATE_LIMIT_PERIOD;
        appLimits[1] = RATE_LIMIT_THRESHOLD;
        appLimits[2] = GAS_LIMIT_PERIOD;
        appLimits[3] = GAS_LIMIT_THRESHOLD;

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(
            "test",
            parentContract,
            initialContracts,
            [appLimits[0], appLimits[1], appLimits[2], appLimits[3]],
            new address[](0)
        );

        // Remove contracts
        address[] memory contractsToRemove = new address[](2);
        contractsToRemove[0] = sponsorContract0;
        contractsToRemove[1] = sponsorContract1;

        vm.prank(address(_kintoWallet));
        vm.expectEmit(true, true, true, true);
        emit IKintoAppRegistry.AppContractsRemoved(parentContract, contractsToRemove);
        _kintoAppRegistry.removeAppContracts(parentContract, contractsToRemove);

        // Verify contracts were removed correctly
        IKintoAppRegistry.Metadata memory metadata = _kintoAppRegistry.getAppMetadata(parentContract);
        assertEq(metadata.appContracts.length, 1);
        assertEq(metadata.appContracts[0], appContract0);

        // Verify childToParentContract mappings were cleared
        assertEq(_kintoAppRegistry.childToParentContract(appContract0), parentContract);
        assertEq(_kintoAppRegistry.childToParentContract(sponsorContract0), address(0));
        assertEq(_kintoAppRegistry.childToParentContract(sponsorContract1), address(0));
    }

    function testRemoveAppContracts_RevertWhen_NotOwner() public {
        address parentContract = address(123);

        // Register initial app
        address[] memory initialContracts = new address[](2);
        initialContracts[0] = appContract0;
        initialContracts[1] = sponsorContract0;

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = RATE_LIMIT_PERIOD;
        appLimits[1] = RATE_LIMIT_THRESHOLD;
        appLimits[2] = GAS_LIMIT_PERIOD;
        appLimits[3] = GAS_LIMIT_THRESHOLD;

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(
            "test",
            parentContract,
            initialContracts,
            [appLimits[0], appLimits[1], appLimits[2], appLimits[3]],
            new address[](0)
        );

        // Try to remove contracts from non-owner address
        address[] memory contractsToRemove = new address[](1);
        contractsToRemove[0] = sponsorContract0;

        vm.prank(_user);
        vm.expectRevert(
            abi.encodeWithSelector(IKintoAppRegistry.InvalidAppOwner.selector, _user, address(_kintoWallet))
        );
        _kintoAppRegistry.removeAppContracts(parentContract, contractsToRemove);
    }

    function testRemoveAppContracts_RevertWhen_ContractNotRegistered() public {
        address parentContract = address(123);

        // Register initial app
        address[] memory initialContracts = new address[](1);
        initialContracts[0] = appContract0;

        uint256[] memory appLimits = new uint256[](4);
        appLimits[0] = RATE_LIMIT_PERIOD;
        appLimits[1] = RATE_LIMIT_THRESHOLD;
        appLimits[2] = GAS_LIMIT_PERIOD;
        appLimits[3] = GAS_LIMIT_THRESHOLD;

        vm.prank(address(_kintoWallet));
        _kintoAppRegistry.registerApp(
            "test",
            parentContract,
            initialContracts,
            [appLimits[0], appLimits[1], appLimits[2], appLimits[3]],
            new address[](0)
        );

        // Try to remove a contract that's not registered
        address[] memory contractsToRemove = new address[](1);
        contractsToRemove[0] = sponsorContract0;

        vm.prank(address(_kintoWallet));
        vm.expectRevert(abi.encodeWithSelector(IKintoAppRegistry.ContractNotRegistered.selector, sponsorContract0));
        _kintoAppRegistry.removeAppContracts(parentContract, contractsToRemove);
    }

    /* ============ Helpers ============ */

    // Helper function to mock contract bytecode
    function mockContractBytecode(address _contract) internal {
        vm.etch(_contract, hex"00"); // Minimal bytecode
    }
}

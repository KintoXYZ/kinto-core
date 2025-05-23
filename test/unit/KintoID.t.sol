// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/Strings.sol";

import "@kinto-core/KintoID.sol";
import "@kinto-core/interfaces/IKintoID.sol";

import "@kinto-core-test/SharedSetup.t.sol";
import "@kinto-core-test/helpers/UUPSProxy.sol";

contract KintoIDv2 is KintoID {
    constructor(address _walletFactory, address _faucet) KintoID(_walletFactory, _faucet) {}

    function newFunction() public pure returns (uint256) {
        return 1;
    }
}

contract KintoIDTest is SharedSetup {
    function setUp() public virtual override {
        super.setUp();

        // upgrade KintoId to undo the harness
        vm.startPrank(_owner);
        _kintoID.upgradeTo(address(new KintoID(address(_walletFactory), address(_faucet))));
        vm.stopPrank();
    }

    function testUp() public override {
        assertEq(_kintoID.name(), "Kinto ID");
        assertEq(_kintoID.symbol(), "KINTOID");

        vm.startPrank(_owner);
        KintoIDv2 _implementationWithFaucet = new KintoIDv2(address(_walletFactory), address(_faucet));
        _kintoID.upgradeTo(address(_implementationWithFaucet));
        vm.stopPrank();
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        vm.startPrank(_owner);
        KintoIDv2 _implementationV2 = new KintoIDv2(address(_walletFactory), address(_faucet));
        _kintoID.upgradeTo(address(_implementationV2));

        // ensure that the _proxy is now pointing to the new implementation
        assertEq(KintoIDv2(address(_kintoID)).newFunction(), 1);
        vm.stopPrank();
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner() public {
        KintoIDv2 _implementationV2 = new KintoIDv2(address(_walletFactory), address(_faucet));

        bytes memory err = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(address(this)),
            " is missing role ",
            Strings.toHexString(uint256(_kintoID.UPGRADER_ROLE()), 32)
        );
        vm.expectRevert(err);
        _kintoID.upgradeTo(address(_implementationV2));
    }

    function testAuthorizedCanUpgrade() public {
        assertEq(false, _kintoID.hasRole(_kintoID.UPGRADER_ROLE(), _upgrader));

        vm.startPrank(_owner);
        _kintoID.grantRole(_kintoID.UPGRADER_ROLE(), _upgrader);
        vm.stopPrank();

        // upgrade from the _upgrader account
        assertEq(true, _kintoID.hasRole(_kintoID.UPGRADER_ROLE(), _upgrader));

        KintoIDv2 _implementationV2 = new KintoIDv2(address(_walletFactory), address(_faucet));
        vm.prank(_upgrader);
        _kintoID.upgradeTo(address(_implementationV2));

        // re-wrap the _proxy
        assertEq(KintoIDv2(address(_kintoID)).newFunction(), 1);
    }

    /* ============ Mint tests ============ */

    function testMintIndividualKYC() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](0);
        vm.startPrank(_kycProvider);
        assertEq(_kintoID.isKYC(_user), false);

        _kintoID.mintIndividualKyc(sigdata, traits);

        assertEq(_kintoID.isKYC(_user), true);
        assertEq(_kintoID.isIndividual(_user), true);
        assertEq(_kintoID.mintedAt(_user), block.timestamp);
        assertEq(_kintoID.hasTrait(_user, 1), false);
        assertEq(_kintoID.hasTrait(_user, 2), false);
        assertEq(_kintoID.balanceOf(_user), 1);
        assertEq(address(_user).balance, 1 ether / 2000);
    }

    function testMintCompanyKYC() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](2);
        traits[0] = 2;
        traits[1] = 5;
        vm.startPrank(_kycProvider);
        _kintoID.mintCompanyKyc(sigdata, traits);
        assertEq(_kintoID.isKYC(_user), true);
        assertEq(_kintoID.isCompany(_user), true);
        assertEq(_kintoID.mintedAt(_user), block.timestamp);
        assertEq(_kintoID.hasTrait(_user, 1), false);
        assertEq(_kintoID.hasTrait(_user, 2), true);
        assertEq(_kintoID.hasTrait(_user, 5), true);
        assertEq(_kintoID.balanceOf(_user), 1);
        assertEq(address(_user).balance, 1 ether / 2000);
    }

    function testMintIndividualKYC_RevertWhen_InvalidSender() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](1);
        traits[0] = 1;
        vm.startPrank(_user);
        vm.expectRevert(IKintoID.InvalidProvider.selector);
        _kintoID.mintIndividualKyc(sigdata, traits);
    }

    function testMintIndividualKYC_RevertWhen_InvalidSigner() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, 5, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](1);
        traits[0] = 1;
        vm.startPrank(_kycProvider);
        vm.expectRevert(IKintoID.InvalidSigner.selector);
        _kintoID.mintIndividualKyc(sigdata, traits);
    }

    function testMintIndividualKYC_RevertWhen_InvalidNonce() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](1);
        traits[0] = 1;
        vm.startPrank(_kycProvider);
        _kintoID.mintIndividualKyc(sigdata, traits);
        vm.expectRevert(IKintoID.InvalidNonce.selector);
        _kintoID.mintIndividualKyc(sigdata, traits);
    }

    function testMintIndividualKYC_RevertWhen_ExpiredSignature() public {
        vm.warp(block.timestamp + 1000);
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp - 1000);

        uint16[] memory traits = new uint16[](1);
        traits[0] = 1;

        vm.prank(_kycProvider);
        vm.expectRevert(IKintoID.SignatureExpired.selector);
        _kintoID.mintIndividualKyc(sigdata, traits);
    }

    function testMintIndividualKYC_RevertWhen_AlreadyMinted() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](0);

        vm.prank(_kycProvider);
        _kintoID.mintIndividualKyc(sigdata, traits);

        // try minting again should revert
        sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        vm.expectRevert(IKintoID.BalanceNotZero.selector);
        vm.prank(_kycProvider);
        _kintoID.mintIndividualKyc(sigdata, traits);
    }

    /* ============ Burn tests ============ */

    function testBurn_RevertWhen_UsingBurn() public {
        vm.expectRevert(abi.encodeWithSelector(IKintoID.MethodNotAllowed.selector, "Use burnKYC instead"));
        _kintoID.burn(1);
    }

    function testBurn_RevertWhen_BurnIsCalled() public {
        approveKYC(_kycProvider, _user, _userPk);
        uint256 tokenIdx = _kintoID.tokenOfOwnerByIndex(_user, 0);
        vm.prank(_user);
        vm.expectRevert(abi.encodeWithSelector(IKintoID.MethodNotAllowed.selector, "Use burnKYC instead"));
        _kintoID.burn(tokenIdx);
    }

    function testBurnKYC() public {
        approveKYC(_kycProvider, _user, _userPk);

        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        vm.prank(_kycProvider);
        _kintoID.burnKYC(sigdata);
        assertEq(_kintoID.balanceOf(_user), 0);
    }

    function testBurnKYC_WhenCallerIsNotProvider() public {
        approveKYC(_kycProvider, _user, _userPk);

        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        vm.expectRevert(IKintoID.InvalidProvider.selector);
        vm.startPrank(_user);
        _kintoID.burnKYC(sigdata);
    }

    function testBurnKYC_WhenUserIsNotKYCd() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        vm.expectRevert(IKintoID.NothingToBurn.selector);
        vm.prank(_kycProvider);
        _kintoID.burnKYC(sigdata);
    }

    function testBurnKYC_WhenBurningTwice() public {
        approveKYC(_kycProvider, _user, _userPk);

        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        vm.prank(_kycProvider);
        _kintoID.burnKYC(sigdata);

        sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        vm.expectRevert(IKintoID.NothingToBurn.selector);
        vm.prank(_kycProvider);
        _kintoID.burnKYC(sigdata);
    }

    /* ============ Monitor tests ============ */

    function testMonitorNoChanges() public {
        vm.startPrank(_kycProvider);
        _kintoID.monitor(new address[](0), new IKintoID.MonitorUpdateData[][](0));
        assertEq(_kintoID.lastMonitoredAt(), block.timestamp);
    }

    function test_RevertWhen_LenghtMismatch() public {
        vm.expectRevert(IKintoID.LengthMismatch.selector);
        vm.prank(_kycProvider);
        _kintoID.monitor(new address[](2), new IKintoID.MonitorUpdateData[][](1));
    }

    function test_RevertWhen_TooManyAccounts() public {
        vm.expectRevert(IKintoID.AccountsAmountExceeded.selector);
        vm.prank(_kycProvider);
        _kintoID.monitor(new address[](201), new IKintoID.MonitorUpdateData[][](201));
    }

    function test_RevertWhen_CallerIsNotProvider(address someone) public {
        vm.assume(someone != _kycProvider);
        bytes memory err = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(address(this)),
            " is missing role ",
            Strings.toHexString(uint256(_kintoID.KYC_PROVIDER_ROLE()), 32)
        );
        vm.expectRevert(err);
        _kintoID.monitor(new address[](0), new IKintoID.MonitorUpdateData[][](0));
    }

    function testIsKYC_WhenMonitorExpires() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](0);
        vm.startPrank(_kycProvider);
        _kintoID.mintIndividualKyc(sigdata, traits);

        assertEq(_kintoID.isKYC(_user), true);

        vm.warp(block.timestamp + 13 days);

        assertEq(_kintoID.isKYC(_user), false);
    }

    function testIsSanctionsMonitored() public {
        vm.prank(_kycProvider);
        _kintoID.monitor(new address[](0), new IKintoID.MonitorUpdateData[][](0));
        assertEq(_kintoID.isSanctionsMonitored(1), true);

        vm.warp(block.timestamp + 7 days);

        assertEq(_kintoID.isSanctionsMonitored(8), true);
        assertEq(_kintoID.isSanctionsMonitored(6), false);
    }

    function testMonitor_WhenPassingTraitsAndSactions() public {
        approveKYC(_kycProvider, _user, _userPk);

        // monitor
        address[] memory accounts = new address[](1);
        accounts[0] = _user;

        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](4);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5); // add trait 5
        updates[0][1] = IKintoID.MonitorUpdateData(true, false, 1); // remove trait 1
        updates[0][2] = IKintoID.MonitorUpdateData(true, true, 6); // add trait 6
        updates[0][3] = IKintoID.MonitorUpdateData(true, false, 2); // remove trait 2

        vm.prank(_kycProvider);
        _kintoID.monitor(accounts, updates);

        assertEq(_kintoID.hasTrait(_user, 5), true);
        assertEq(_kintoID.hasTrait(_user, 1), false);
        assertEq(_kintoID.hasTrait(_user, 6), true);
        assertEq(_kintoID.hasTrait(_user, 2), false);

        updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(false, true, 3); // add sanction 3

        vm.prank(_kycProvider);
        _kintoID.monitor(accounts, updates);

        assertEq(_kintoID.isSanctionsSafeIn(_user, 3), false);

        vm.warp(block.timestamp + 12 days);

        updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(false, false, 3); // remove sanction 3

        vm.prank(_kycProvider);
        _kintoID.monitor(accounts, updates);

        assertEq(_kintoID.isSanctionsSafeIn(_user, 3), true);
    }

    /* ============ Trait tests ============ */

    function testAddTrait() public {
        approveKYC(_kycProvider, _user, _userPk);
        vm.prank(_kycProvider);
        _kintoID.addTrait(_user, 1);
        assertEq(_kintoID.lastMonitoredAt(), block.timestamp);
    }

    function testAddTrait_RevertWhen_CallerIsNotProvider() public {
        approveKYC(_kycProvider, _user, _userPk);
        bytes memory err = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(_user),
            " is missing role ",
            Strings.toHexString(uint256(_kintoID.KYC_PROVIDER_ROLE()), 32)
        );
        vm.expectRevert(err);
        vm.prank(_user);
        _kintoID.addTrait(_user, 1);
    }

    function testAddTrait_RevertWhen_UserIsNotKYCd() public {
        assertEq(_kintoID.isKYC(_user), false);
        vm.expectRevert(IKintoID.KYCRequired.selector);
        vm.prank(_kycProvider);
        _kintoID.addTrait(_user, 1);
    }

    function testRemoveTrait() public {
        vm.startPrank(_kycProvider);
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](1);
        traits[0] = 1;
        _kintoID.mintIndividualKyc(sigdata, traits);
        _kintoID.addTrait(_user, 1);
        assertEq(_kintoID.hasTrait(_user, 1), true);
        _kintoID.removeTrait(_user, 1);
        assertEq(_kintoID.hasTrait(_user, 1), false);
        assertEq(_kintoID.lastMonitoredAt(), block.timestamp);
    }

    function testRemoveTrait_RevertWhen_CallerIsNotProvider() public {
        approveKYC(_kycProvider, _user, _userPk);

        bytes memory err = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(_user),
            " is missing role ",
            Strings.toHexString(uint256(_kintoID.KYC_PROVIDER_ROLE()), 32)
        );
        vm.expectRevert(err);
        vm.prank(_user);
        _kintoID.removeTrait(_user, 1);
    }

    function testRemoveTrait_RevertWhen_AccountIsNotKYCd() public {
        vm.expectRevert(IKintoID.KYCRequired.selector);
        vm.prank(_kycProvider);
        _kintoID.removeTrait(_user, 1);
    }

    function testTrais() public {
        approveKYC(_kycProvider, _user, _userPk);

        vm.startPrank(_kycProvider);

        _kintoID.addTrait(_user, 0);
        _kintoID.addTrait(_user, 1);
        _kintoID.addTrait(_user, 2);

        vm.stopPrank();

        bool[] memory traits = _kintoID.traits(_user);
        assertEq(traits[0], true);
        assertEq(traits[1], true);
        assertEq(traits[2], true);
        assertEq(traits[3], false);
    }

    /* ============ Sanction tests ============ */

    function testAddSanction() public {
        addKYC();

        vm.startPrank(_kycProvider);

        _kintoID.addSanction(_user, 1);

        assertEq(_kintoID.isSanctionsSafeIn(_user, 1), false);
        assertEq(_kintoID.isSanctionsSafe(_user), false);
        assertEq(_kintoID.lastMonitoredAt(), block.timestamp);
    }

    function testAddSanction_WhenNotConfirmed() public {
        addKYC();

        vm.startPrank(_kycProvider);

        _kintoID.addSanction(_user, 1);

        assertEq(_kintoID.isSanctionsSafeIn(_user, 1), false);
        assertEq(_kintoID.isSanctionsSafe(_user), false);
        assertEq(_kintoID.lastMonitoredAt(), block.timestamp);
        assertEq(_kintoID.sanctionedAt(_user), block.timestamp);

        uint256 sanctionTime = block.timestamp;

        vm.warp(block.timestamp + 3 days + 1);

        assertEq(_kintoID.isSanctionsSafeIn(_user, 1), true);
        assertEq(_kintoID.isSanctionsSafe(_user), true);
        assertEq(_kintoID.lastMonitoredAt(), sanctionTime);
        assertEq(_kintoID.sanctionedAt(_user), sanctionTime);
    }

    function testRemoveSancion_RevertWhenInExitWindowPeriod() public {
        addKYC();

        vm.startPrank(_kycProvider);
        _kintoID.addSanction(_user, 1);
        assertEq(_kintoID.isSanctionsSafeIn(_user, 1), false);

        vm.expectRevert(abi.encodeWithSelector(IKintoID.ExitWindowPeriod.selector, _user, _kintoID.sanctionedAt(_user)));
        _kintoID.removeSanction(_user, 1);
        vm.stopPrank();
    }

    function testRemoveSancion() public {
        addKYC();

        vm.startPrank(_kycProvider);
        _kintoID.addSanction(_user, 1);
        assertEq(_kintoID.isSanctionsSafeIn(_user, 1), false);

        // has to wait for the exit window to be over
        vm.warp(block.timestamp + 12 days);

        _kintoID.removeSanction(_user, 1);
        vm.stopPrank();

        assertEq(_kintoID.isSanctionsSafeIn(_user, 1), true);
        assertEq(_kintoID.isSanctionsSafe(_user), true);
        assertEq(_kintoID.lastMonitoredAt(), block.timestamp);
    }

    function testAddSanction_BlockedDuringExitWindow() public {
        addKYC();

        vm.startPrank(_kycProvider);

        // Add initial sanction
        _kintoID.addSanction(_user, 1);
        uint256 sanctionTime = block.timestamp;

        // Try adding another sanction during exit window
        vm.expectRevert(abi.encodeWithSelector(IKintoID.ExitWindowPeriod.selector, _user, sanctionTime));
        _kintoID.addSanction(_user, 2);

        // Try at different times during window
        vm.warp(block.timestamp + 5 days);
        vm.expectRevert(abi.encodeWithSelector(IKintoID.ExitWindowPeriod.selector, _user, sanctionTime));
        _kintoID.addSanction(_user, 2);

        // Should succeed after window
        vm.warp(sanctionTime + 12 days + 1);
        _kintoID.addSanction(_user, 2);

        vm.stopPrank();
    }

    function testRemoveSanction_BlockedDuringExitWindow() public {
        addKYC();

        vm.startPrank(_kycProvider);

        // Add sanction
        _kintoID.addSanction(_user, 1);
        uint256 sanctionTime = block.timestamp;

        // Try removing during exit window
        vm.expectRevert(abi.encodeWithSelector(IKintoID.ExitWindowPeriod.selector, _user, sanctionTime));
        _kintoID.removeSanction(_user, 1);

        // Try halfway through window
        vm.warp(block.timestamp + 5 days);
        vm.expectRevert(abi.encodeWithSelector(IKintoID.ExitWindowPeriod.selector, _user, sanctionTime));
        _kintoID.removeSanction(_user, 1);

        // Should succeed after window
        vm.warp(sanctionTime + 12 days + 1);
        _kintoID.removeSanction(_user, 1);

        vm.stopPrank();
    }

    function testExitWindow_MultipleSanctions() public {
        addKYC();

        vm.startPrank(_kycProvider);

        // Add first sanction
        _kintoID.addSanction(_user, 1);
        uint256 firstSanctionTime = block.timestamp;

        // Advance past window
        vm.warp(firstSanctionTime + 12 days + 1);

        // Add second sanction
        _kintoID.addSanction(_user, 2);
        uint256 secondSanctionTime = block.timestamp;

        // Try removing first sanction during second's window
        vm.expectRevert(abi.encodeWithSelector(IKintoID.ExitWindowPeriod.selector, _user, secondSanctionTime));
        _kintoID.removeSanction(_user, 1);

        vm.stopPrank();
    }

    function testAddSanction_RevertWhen_CallerIsNotKYCProvider() public {
        approveKYC(_kycProvider, _user, _userPk, new uint16[](1));

        bytes memory err = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(_user),
            " is missing role ",
            Strings.toHexString(uint256(_kintoID.KYC_PROVIDER_ROLE()), 32)
        );
        vm.expectRevert(err);
        vm.prank(_user);
        _kintoID.addSanction(_user2, 1);
    }

    function testRemoveSanction_RevertWhen_CallerIsNotKYCProvider() public {
        approveKYC(_kycProvider, _user, _userPk);

        vm.prank(_kycProvider);
        _kintoID.addSanction(_user, 1);
        assertEq(_kintoID.isSanctionsSafeIn(_user, 1), false);

        bytes memory err = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(_user),
            " is missing role ",
            Strings.toHexString(uint256(_kintoID.KYC_PROVIDER_ROLE()), 32)
        );
        vm.expectRevert(err);
        vm.prank(_user);
        _kintoID.removeSanction(_user2, 1);
    }

    function testAddSanction_RevertWhen_AccountIsNotKYCd() public {
        vm.expectRevert(IKintoID.KYCRequired.selector);
        vm.prank(_kycProvider);
        _kintoID.addSanction(_user, 1);
    }

    function testRemoveSanction_RevertWhen_AccountIsNotKYCd() public {
        vm.expectRevert(IKintoID.KYCRequired.selector);
        vm.prank(_kycProvider);
        _kintoID.removeSanction(_user, 1);
    }

    function testConfirmSanction() public {
        // First approve KYC and add a sanction
        approveKYC(_kycProvider, _user, _userPk);

        vm.startPrank(_kycProvider);
        _kintoID.addSanction(_user, 1);
        vm.stopPrank();

        // Confirm the sanction
        vm.expectEmit(true, false, false, true);
        emit KintoID.SanctionConfirmed(_user, block.timestamp);

        vm.prank(_owner);
        _kintoID.confirmSanction(_user);

        // Verify sanction remains active even after 3 days
        vm.warp(block.timestamp + 4 days);

        assertEq(_kintoID.isSanctionsSafeIn(_user, 1), false);
        assertEq(_kintoID.isSanctionsSafe(_user), false);
        assertEq(_kintoID.sanctionedAt(_user), 0); // Timestamp should be reset to 0
    }

    function testConfirmSanction_RevertWhen_CallerNotGovernance() public {
        // First approve KYC and add a sanction
        approveKYC(_kycProvider, _user, _userPk);

        vm.prank(_kycProvider);
        _kintoID.addSanction(_user, 1);

        // Try to confirm sanction from non-governance address
        bytes memory err = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(_user),
            " is missing role ",
            Strings.toHexString(uint256(_kintoID.GOVERNANCE_ROLE()), 32)
        );

        vm.expectRevert(err);
        vm.prank(_user);
        _kintoID.confirmSanction(_user);
    }

    function testConfirmSanction_RevertWhen_NoSanctionExists() public {
        // Try to confirm non-existent sanction
        vm.prank(_owner);
        vm.expectRevert(abi.encodeWithSelector(IKintoID.NoActiveSanction.selector, _user));
        _kintoID.confirmSanction(_user);

        // Verify no changes occurred
        assertEq(_kintoID.sanctionedAt(_user), 0);
        assertEq(_kintoID.isSanctionsSafe(_user), true);
    }

    /* ============ Multi-sanction tests ============ */

    function testMultipleSanctionsHandling() public {
        addKYC();

        vm.startPrank(_kycProvider);

        // Add first sanction
        _kintoID.addSanction(_user, 10);

        // Wait past exit window
        vm.warp(block.timestamp + 13 days);

        // Add another sanction
        _kintoID.addSanction(_user, 20);

        // Verify both sanctions are active
        assertEq(_kintoID.isSanctionsSafeIn(_user, 10), false);
        assertEq(_kintoID.isSanctionsSafeIn(_user, 20), false);

        // Remove one sanction after exit window
        vm.warp(block.timestamp + 13 days);
        _kintoID.removeSanction(_user, 10);

        // Verify correct sanction state
        assertEq(_kintoID.isSanctionsSafeIn(_user, 10), true);
        assertEq(_kintoID.isSanctionsSafeIn(_user, 20), false);

        vm.stopPrank();
    }

    function testMonitorWithMultipleAccountsAndSanctions() public {
        // Approve KYC for multiple users
        approveKYC(_kycProvider, _user, _userPk);
        approveKYC(_kycProvider, _user2, _user2Pk);

        // Create monitor update data
        address[] memory accounts = new address[](2);
        accounts[0] = _user;
        accounts[1] = _user2;

        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](2);

        // Updates for first user
        updates[0] = new IKintoID.MonitorUpdateData[](3);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5); // Add trait 5
        updates[0][1] = IKintoID.MonitorUpdateData(false, true, 10); // Add sanction 10
        updates[0][2] = IKintoID.MonitorUpdateData(true, true, 15); // Add trait 15

        // Updates for second user
        updates[1] = new IKintoID.MonitorUpdateData[](2);
        updates[1][0] = IKintoID.MonitorUpdateData(true, true, 20); // Add trait 20
        updates[1][1] = IKintoID.MonitorUpdateData(false, true, 30); // Add sanction 30

        // Execute monitor
        vm.prank(_kycProvider);
        _kintoID.monitor(accounts, updates);

        // Verify updates were applied correctly
        assertEq(_kintoID.hasTrait(_user, 5), true);
        assertEq(_kintoID.hasTrait(_user, 15), true);
        assertEq(_kintoID.isSanctionsSafeIn(_user, 10), false);

        assertEq(_kintoID.hasTrait(_user2, 20), true);
        assertEq(_kintoID.isSanctionsSafeIn(_user2, 30), false);
    }

    /* ============ TransferOnRecovery tests ============ */

    function testTransferOnRecovery() public {
        // Setup KYC for initial user
        approveKYC(_kycProvider, _user, _userPk);
        uint256 tokenId = _kintoID.tokenOfOwnerByIndex(_user, 0);

        // Verify initial state
        assertEq(_kintoID.balanceOf(_user), 1);
        assertEq(_kintoID.balanceOf(_user2), 0);
        assertEq(_kintoID.ownerOf(tokenId), _user);

        // Execute recovery transfer
        vm.prank(address(_walletFactory));
        _kintoID.transferOnRecovery(_user, _user2);

        // Verify transfer completed
        assertEq(_kintoID.balanceOf(_user), 0);
        assertEq(_kintoID.balanceOf(_user2), 1);
        assertEq(_kintoID.ownerOf(tokenId), _user2);

        // Verify recovery target was cleared
        assertEq(_kintoID.recoveryTargets(_user), address(0));
    }

    function testTransferOnRecovery_RevertWhen_BalanceInvalid() public {
        // Setup KYC for both users
        approveKYC(_kycProvider, _user, _userPk);
        approveKYC(_kycProvider, _user2, _user2Pk);

        // Try recovery when target already has a token
        vm.expectRevert("Invalid transfer");
        vm.prank(address(_walletFactory));
        _kintoID.transferOnRecovery(_user, _user2);
    }

    function testTransferOnRecovery_RevertWhen_UnauthorizedCaller() public {
        // Setup KYC
        approveKYC(_kycProvider, _user, _userPk);

        // Try recovery from unauthorized address
        vm.expectRevert("Only the wallet factory or admins can trigger this");
        vm.prank(_user);
        _kintoID.transferOnRecovery(_user, _user2);
    }

    function testTransferOnRecovery_AdminCanExecute() public {
        // Setup KYC for initial user
        approveKYC(_kycProvider, _user, _userPk);
        uint256 tokenId = _kintoID.tokenOfOwnerByIndex(_user, 0);

        // Execute recovery transfer as admin
        vm.prank(_owner);
        _kintoID.transferOnRecovery(_user, _user2);

        // Verify transfer completed
        assertEq(_kintoID.balanceOf(_user2), 1);
        assertEq(_kintoID.ownerOf(tokenId), _user2);
    }

    /* ============ Transfer tests ============ */

    function test_RevertWhen_TransfersAreDisabled() public {
        approveKYC(_kycProvider, _user, _userPk);
        uint256 tokenIdx = _kintoID.tokenOfOwnerByIndex(_user, 0);
        vm.prank(_user);
        vm.expectRevert(IKintoID.OnlyMintBurnOrTransfer.selector);
        _kintoID.safeTransferFrom(_user, _user2, tokenIdx);
    }

    function testDappSignature() public {
        // vm.startPrank(_kycProvider);
        // bytes memory sig = hex"0fcafa82e64fcfd3c38209e23270274132e88061f1718c7ff45e8c0ddbbe7cdd59b5af57e10a5d8221baa6ae37b57d02acace7e25fc29cb4025f15269e0939aa1b";
        // bool valid = _auxDappSignature(
        //     IKintoID.SignatureData(
        //         0xf1cE2ca79D49B431652F9597947151cf21efB9C3,
        //         0xf1cE2ca79D49B431652F9597947151cf21efB9C3,
        //         0,
        //         1680614821,
        //         sig
        //     )
        // );
        // assertEq(valid, true);
    }

    /* ============ Edge case tests ============ */

    function testMonitorWithNonKYCdAccount() public {
        // Create data with KYCd and non-KYCd users
        address[] memory accounts = new address[](2);
        accounts[0] = address(0x123); // Non-KYCd address
        accounts[1] = _user;

        // Add KYC for one user only
        approveKYC(_kycProvider, _user, _userPk);

        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](2);

        // Updates for non-KYCd user (should be skipped)
        updates[0] = new IKintoID.MonitorUpdateData[](1);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);

        // Updates for KYCd user
        updates[1] = new IKintoID.MonitorUpdateData[](1);
        updates[1][0] = IKintoID.MonitorUpdateData(true, true, 10);

        // Execute monitor
        vm.prank(_kycProvider);
        _kintoID.monitor(accounts, updates);

        // Verify only valid user was updated
        assertEq(_kintoID.hasTrait(_user, 10), true);
    }

    function testTransferOnRecovery_BlockedForSanctionedAccount() public {
        // Setup KYC and add sanction
        approveKYC(_kycProvider, _user, _userPk);

        vm.prank(_kycProvider);
        _kintoID.addSanction(_user, 5);

        // Attempt transfer on recovery should fail due to sanctions
        vm.expectRevert(IKintoID.OnlyMintBurnOrTransfer.selector);
        vm.prank(address(_walletFactory));
        _kintoID.transferOnRecovery(_user, _user2);
    }

    function testIsKYCWithSanctionsExpired() public {
        // Setup KYC and add sanction
        approveKYC(_kycProvider, _user, _userPk);

        vm.prank(_kycProvider);
        _kintoID.addSanction(_user, 5);

        // User should not be KYC'd when sanctioned
        assertEq(_kintoID.isKYC(_user), false);

        // After sanction expiry period
        vm.warp(block.timestamp + 3 days + 1);

        // User should now be KYC'd again (sanction expired)
        assertEq(_kintoID.isKYC(_user), true);
    }

    function testSanctionsAfterGovernanceConfirmation() public {
        // Setup KYC and add sanction
        approveKYC(_kycProvider, _user, _userPk);

        vm.prank(_kycProvider);
        _kintoID.addSanction(_user, 5);

        // Governance confirms the sanction
        vm.prank(_owner);
        _kintoID.confirmSanction(_user);

        // Sanction should stay active even after the expiry period
        vm.warp(block.timestamp + 4 days);
        assertEq(_kintoID.isKYC(_user), false);

        // Sanction should still be active even after a long time
        vm.warp(block.timestamp + 100 days);
        assertEq(_kintoID.isKYC(_user), false);
    }

    /* ============ Supports Interface tests ============ */

    function testSupportsInterface() public view {
        bytes4 InterfaceERC721Upgradeable = bytes4(keccak256("balanceOf(address)"))
            ^ bytes4(keccak256("ownerOf(uint256)")) ^ bytes4(keccak256("safeTransferFrom(address,address,uint256,bytes)"))
            ^ bytes4(keccak256("safeTransferFrom(address,address,uint256)"))
            ^ bytes4(keccak256("transferFrom(address,address,uint256)")) ^ bytes4(keccak256("approve(address,uint256)"))
            ^ bytes4(keccak256("setApprovalForAll(address,bool)")) ^ bytes4(keccak256("getApproved(uint256)"))
            ^ bytes4(keccak256("isApprovedForAll(address,address)"));

        assertTrue(_kintoID.supportsInterface(InterfaceERC721Upgradeable));
    }

    function addKYC() public {
        vm.startPrank(_kycProvider);
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](1);
        traits[0] = 1;
        _kintoID.mintIndividualKyc(sigdata, traits);
        vm.stopPrank();
    }

    /* ============ Signature Validation Tests ============ */

    function testSignatureForContractSigner_Revert() public {
        // Create a mock contract
        address mockContract = address(new KintoIDv2(address(_walletFactory), address(_faucet)));

        // Try to create signature for a contract (should fail)
        IKintoID.SignatureData memory sigdata = IKintoID.SignatureData({
            signer: mockContract,
            nonce: 0,
            expiresAt: block.timestamp + 1000,
            signature: hex"01"
        });

        uint16[] memory traits = new uint16[](1);

        // Should revert due to contract signer
        vm.prank(_kycProvider);
        vm.expectRevert(IKintoID.SignerNotEOA.selector);
        _kintoID.mintIndividualKyc(sigdata, traits);
    }

    /* ============ Dominate Separator Tests ============ */

    function testDomainSeparatorConsistency() public view {
        // Get domain separator from the contract
        bytes32 contractSeparator = _kintoID.domainSeparator();

        // Manually compute the expected domain separator
        bytes32 expectedSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("KintoID")),
                keccak256(bytes("1")),
                block.chainid,
                address(_kintoID)
            )
        );

        // Verify they match
        assertEq(contractSeparator, expectedSeparator);
    }
}

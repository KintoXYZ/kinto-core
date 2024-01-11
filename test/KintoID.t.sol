// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

import "../src/KintoID.sol";
import "../src/interfaces/IKintoID.sol";

import "./helpers/KYCSignature.sol";
import "./helpers/UUPSProxy.sol";
import {AATestScaffolding} from "./helpers/AATestScaffolding.sol";
import {UserOp} from "./helpers/UserOp.sol";

contract KintoIDv2 is KintoID {
    constructor() KintoID() {}

    function newFunction() public pure returns (uint256) {
        return 1;
    }
}

contract KintoIDTest is KYCSignature, AATestScaffolding, UserOp {
    KintoIDv2 _kintoIDv2;

    function setUp() public {
        vm.chainId(1);
        vm.startPrank(_owner);
        _implementation = new KintoID();

        // deploy _proxy contract and point it to _implementation
        _proxy = new UUPSProxy(address(_implementation), "");

        // wrap in ABI to support easier calls
        _kintoIDv1 = KintoID(address(_proxy));

        // Initialize _proxy
        _kintoIDv1.initialize();
        _kintoIDv1.grantRole(_kintoIDv1.KYC_PROVIDER_ROLE(), _kycProvider);
        vm.stopPrank();
    }

    function testUp() public {
        assertEq(_kintoIDv1.lastMonitoredAt(), block.timestamp);
        assertEq(_kintoIDv1.name(), "Kinto ID");
        assertEq(_kintoIDv1.symbol(), "KINTOID");
    }

    // Upgrade Tests

    function testOwnerCanUpgrade() public {
        vm.startPrank(_owner);
        KintoIDv2 _implementationV2 = new KintoIDv2();
        _kintoIDv1.upgradeTo(address(_implementationV2));

        // ensure that the _proxy is now pointing to the new implementation
        _kintoIDv2 = KintoIDv2(address(_proxy));
        assertEq(_kintoIDv2.newFunction(), 1);
        vm.stopPrank();
    }

    function test_RevertWhen_OthersCannotUpgrade() public {
        KintoIDv2 _implementationV2 = new KintoIDv2();

        bytes memory err = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(address(this)),
            " is missing role ",
            Strings.toHexString(uint256(_implementationV2.UPGRADER_ROLE()), 32)
        );
        vm.expectRevert(err);
        _kintoIDv1.upgradeTo(address(_implementationV2));
    }

    function testAuthorizedCanUpgrade() public {
        assertEq(false, _kintoIDv1.hasRole(_kintoIDv1.UPGRADER_ROLE(), _upgrader));

        vm.startPrank(_owner);
        _kintoIDv1.grantRole(_kintoIDv1.UPGRADER_ROLE(), _upgrader);
        vm.stopPrank();

        // upgrade from the _upgrader account
        assertEq(true, _kintoIDv1.hasRole(_kintoIDv1.UPGRADER_ROLE(), _upgrader));

        KintoIDv2 _implementationV2 = new KintoIDv2();
        vm.prank(_upgrader);
        _kintoIDv1.upgradeTo(address(_implementationV2));

        // re-wrap the _proxy
        _kintoIDv2 = KintoIDv2(address(_proxy));
        assertEq(_kintoIDv2.newFunction(), 1);
    }

    // Mint Tests

    function testMintIndividualKYC() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](0);
        vm.startPrank(_kycProvider);
        assertEq(_kintoIDv1.isKYC(_user), false);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        assertEq(_kintoIDv1.isKYC(_user), true);
        assertEq(_kintoIDv1.isIndividual(_user), true);
        assertEq(_kintoIDv1.mintedAt(_user), block.timestamp);
        assertEq(_kintoIDv1.hasTrait(_user, 1), false);
        assertEq(_kintoIDv1.hasTrait(_user, 2), false);
        assertEq(_kintoIDv1.balanceOf(_user), 1);
    }

    function testMintCompanyKYC() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](2);
        traits[0] = 2;
        traits[1] = 5;
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintCompanyKyc(sigdata, traits);
        assertEq(_kintoIDv1.isKYC(_user), true);
        assertEq(_kintoIDv1.isCompany(_user), true);
        assertEq(_kintoIDv1.mintedAt(_user), block.timestamp);
        assertEq(_kintoIDv1.hasTrait(_user, 1), false);
        assertEq(_kintoIDv1.hasTrait(_user, 2), true);
        assertEq(_kintoIDv1.hasTrait(_user, 5), true);
        assertEq(_kintoIDv1.balanceOf(_user), 1);
    }

    function testMintIndividualKYCWithInvalidSender() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(_user);
        vm.expectRevert("Invalid Provider");
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
    }

    function testMintIndividualKYCWithInvalidSigner() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 5, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(_kycProvider);
        vm.expectRevert("Invalid Signer");
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
    }

    function testMintIndividualKYCWithInvalidNonce() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        vm.expectRevert("Invalid Nonce");
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
    }

    function testMintIndividualKYCWithExpiredSignature() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp - 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(_kycProvider);
        vm.expectRevert("Signature has expired");
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
    }

    // Burn Tests

    function testBurnKYC() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        assertEq(_kintoIDv1.isKYC(_user), true);
        sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        _kintoIDv1.burnKYC(sigdata);
        assertEq(_kintoIDv1.balanceOf(_user), 0);
    }

    function testOnlyProviderCanBurnKYC() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        assertEq(_kintoIDv1.isKYC(_user), true);
        sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        vm.stopPrank();
        vm.startPrank(_user);
        vm.expectRevert("Invalid Provider");
        _kintoIDv1.burnKYC(sigdata);
    }

    function testBurnFailsWithoutMinting() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        vm.startPrank(_kycProvider);
        vm.expectRevert("Nothing to burn");
        _kintoIDv1.burnKYC(sigdata);
    }

    function testBurningTwiceFails() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        assertEq(_kintoIDv1.isKYC(_user), true);
        sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        _kintoIDv1.burnKYC(sigdata);
        sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        vm.expectRevert("Nothing to burn");
        _kintoIDv1.burnKYC(sigdata);
    }

    // Monitor Tests
    function testMonitorNoChanges() public {
        vm.startPrank(_kycProvider);
        _kintoIDv1.monitor(new address[](0), new IKintoID.MonitorUpdateData[][](0));
        assertEq(_kintoIDv1.lastMonitoredAt(), block.timestamp);
    }

    function test_RevertWhen_OnlyProviderCanMonitor(address someone) public {
        vm.assume(someone != _kycProvider);
        bytes memory err = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(address(this)),
            " is missing role ",
            Strings.toHexString(uint256(_kintoIDv1.KYC_PROVIDER_ROLE()), 32)
        );
        vm.expectRevert(err);
        _kintoIDv1.monitor(new address[](0), new IKintoID.MonitorUpdateData[][](0));
    }

    function testIsSanctionsMonitored() public {
        vm.prank(_kycProvider);
        _kintoIDv1.monitor(new address[](0), new IKintoID.MonitorUpdateData[][](0));
        assertEq(_kintoIDv1.isSanctionsMonitored(1), true);

        vm.warp(block.timestamp + 7 days);

        assertEq(_kintoIDv1.isSanctionsMonitored(8), true);
        assertEq(_kintoIDv1.isSanctionsMonitored(6), false);
    }

    function testSettingTraitsAndSanctions() public {
        approveKYC(_kycProvider, _user, _userPk);

        // monitor
        address[] memory accounts = new address[](1);
        accounts[0] = _user;
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](2);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);
        updates[0][1] = IKintoID.MonitorUpdateData(true, false, 1); // remove 1

        vm.prank(_kycProvider);
        _kintoIDv1.monitor(accounts, updates);

        assertEq(_kintoIDv1.hasTrait(_user, 5), true);
        assertEq(_kintoIDv1.hasTrait(_user, 1), false);
        assertEq(_kintoIDv1.isSanctionsSafeIn(_user, 5), true);
        assertEq(_kintoIDv1.isSanctionsSafeIn(_user, 1), true);
    }

    /* ============ Trait Tests ============ */

    function testAddTrait_WhenCallerIsProvider() public {
        approveKYC(_kycProvider, _user, _userPk);
        vm.prank(_kycProvider);
        _kintoIDv1.addTrait(_user, 1);
        assertEq(_kintoIDv1.lastMonitoredAt(), block.timestamp);
    }

    function testAddTrait_RevertWhen_CallerIsNotProvider() public {
        approveKYC(_kycProvider, _user, _userPk);
        bytes memory err = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(_user),
            " is missing role ",
            Strings.toHexString(uint256(_kintoIDv1.KYC_PROVIDER_ROLE()), 32)
        );
        vm.expectRevert(err);
        vm.prank(_user);
        _kintoIDv1.addTrait(_user, 1);
    }

    function testAddTrait_RevertWhen_UserIsNotKYCd() public {
        assertEq(_kintoIDv1.isKYC(_user), false);
        vm.expectRevert("Account must have a KYC token");
        vm.prank(_kycProvider);
        _kintoIDv1.addTrait(_user, 1);
    }

    function testRemoveTrait_WhenCallerIsProvider() public {
        vm.startPrank(_kycProvider);
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        _kintoIDv1.addTrait(_user, 1);
        assertEq(_kintoIDv1.hasTrait(_user, 1), true);
        _kintoIDv1.removeTrait(_user, 1);
        assertEq(_kintoIDv1.hasTrait(_user, 1), false);
        assertEq(_kintoIDv1.lastMonitoredAt(), block.timestamp);
    }

    function testRemoveTrait_RevertWhen_CallerIsNotProvider() public {
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        approveKYC(_kycProvider, _user, _userPk, traits);
        assertEq(_kintoIDv1.hasTrait(_user, 1), true);

        bytes memory err = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(_user),
            " is missing role ",
            Strings.toHexString(uint256(_kintoIDv1.KYC_PROVIDER_ROLE()), 32)
        );
        vm.expectRevert(err);
        vm.prank(_user);
        _kintoIDv1.removeTrait(_user, 1);
    }

    /* ============ Sanction Tests ============ */

    function testProviderCanAddSanction() public {
        vm.startPrank(_kycProvider);
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        _kintoIDv1.addSanction(_user, 1);
        assertEq(_kintoIDv1.isSanctionsSafeIn(_user, 1), false);
        assertEq(_kintoIDv1.isSanctionsSafe(_user), false);
        assertEq(_kintoIDv1.lastMonitoredAt(), block.timestamp);
    }

    function testProviderCanRemoveSancion() public {
        vm.startPrank(_kycProvider);
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoIDv1, _user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        _kintoIDv1.addSanction(_user, 1);
        assertEq(_kintoIDv1.isSanctionsSafeIn(_user, 1), false);
        _kintoIDv1.removeSanction(_user, 1);
        assertEq(_kintoIDv1.isSanctionsSafeIn(_user, 1), true);
        assertEq(_kintoIDv1.isSanctionsSafe(_user), true);
        assertEq(_kintoIDv1.lastMonitoredAt(), block.timestamp);
    }

    function testAddSanction_RevertWhen_CallerIsNotKYCProvider() public {
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        approveKYC(_kycProvider, _user, _userPk, traits);

        bytes memory err = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(_user),
            " is missing role ",
            Strings.toHexString(uint256(_kintoIDv1.KYC_PROVIDER_ROLE()), 32)
        );
        vm.expectRevert(err);
        vm.prank(_user);
        _kintoIDv1.addSanction(_user2, 1);
    }

    function testRemoveSanction_RevertWhen_CallerIsNotKYCProvider() public {
        approveKYC(_kycProvider, _user, _userPk);

        vm.prank(_kycProvider);
        _kintoIDv1.addSanction(_user, 1);
        assertEq(_kintoIDv1.isSanctionsSafeIn(_user, 1), false);

        bytes memory err = abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(_user),
            " is missing role ",
            Strings.toHexString(uint256(_kintoIDv1.KYC_PROVIDER_ROLE()), 32)
        );
        vm.expectRevert(err);
        vm.prank(_user);
        _kintoIDv1.removeSanction(_user2, 1);
    }

    /* ============ Transfer Tests ============ */

    function test_RevertWhen_TransfersAreDisabled() public {
        approveKYC(_kycProvider, _user, _userPk);
        uint256 tokenIdx = _kintoIDv1.tokenOfOwnerByIndex(_user, 0);
        vm.prank(_user);
        vm.expectRevert("Only mint or burn transfers are allowed");
        _kintoIDv1.safeTransferFrom(_user, _user2, tokenIdx);
    }

    function test_RevertWhen_BurnIsCalled() public {
        approveKYC(_kycProvider, _user, _userPk);
        uint256 tokenIdx = _kintoIDv1.tokenOfOwnerByIndex(_user, 0);
        vm.prank(_user);
        vm.expectRevert("Use burnKYC instead");
        _kintoIDv1.burn(tokenIdx);
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
}

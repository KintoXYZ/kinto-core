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
        updates[0][2] = IKintoID.MonitorUpdateData(false, true, 6); // add sanction 6
        updates[0][3] = IKintoID.MonitorUpdateData(false, false, 2); // remove sanction 2

        vm.prank(_kycProvider);
        _kintoID.monitor(accounts, updates);

        assertEq(_kintoID.hasTrait(_user, 5), true);
        assertEq(_kintoID.hasTrait(_user, 1), false);
        assertEq(_kintoID.isSanctionsSafeIn(_user, 5), true);
        assertEq(_kintoID.isSanctionsSafeIn(_user, 1), true);
        assertEq(_kintoID.isSanctionsSafeIn(_user, 6), false);
        assertEq(_kintoID.isSanctionsSafeIn(_user, 2), true);
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
        vm.startPrank(_kycProvider);
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](1);
        traits[0] = 1;
        _kintoID.mintIndividualKyc(sigdata, traits);
        _kintoID.addSanction(_user, 1);
        assertEq(_kintoID.isSanctionsSafeIn(_user, 1), false);
        assertEq(_kintoID.isSanctionsSafe(_user), false);
        assertEq(_kintoID.lastMonitoredAt(), block.timestamp);
    }

    function testRemoveSancion() public {
        vm.startPrank(_kycProvider);
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_kintoID, _user, _userPk, block.timestamp + 1000);
        uint16[] memory traits = new uint16[](1);
        traits[0] = 1;
        _kintoID.mintIndividualKyc(sigdata, traits);
        _kintoID.addSanction(_user, 1);
        assertEq(_kintoID.isSanctionsSafeIn(_user, 1), false);
        _kintoID.removeSanction(_user, 1);
        assertEq(_kintoID.isSanctionsSafeIn(_user, 1), true);
        assertEq(_kintoID.isSanctionsSafe(_user), true);
        assertEq(_kintoID.lastMonitoredAt(), block.timestamp);
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
}

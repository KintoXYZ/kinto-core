// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/tokens/EngenCredits.sol";
import "./SharedSetup.t.sol";

contract EngenCreditsV2 is EngenCredits {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor() EngenCredits() {}
}

contract EngenCreditsTest is SharedSetup {
    function setUp() public override {
        super.setUp();
        fundSponsorForApp(address(_engenCredits));
        registerApp(_owner, "engen credits", address(_engenCredits));
    }

    function testUp() public override {
        super.testUp();
        assertEq(_engenCredits.totalSupply(), 0);
        assertEq(_engenCredits.owner(), _owner);
        assertEq(_engenCredits.transfersEnabled(), false);
        assertEq(_engenCredits.burnsEnabled(), false);
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        vm.startPrank(_owner);
        EngenCreditsV2 _implementationV2 = new EngenCreditsV2();
        _engenCredits.upgradeTo(address(_implementationV2));

        // ensure that the implementation has been upgraded
        EngenCreditsV2 _engenCreditsV2 = EngenCreditsV2(address(_engenCredits));
        assertEq(_engenCreditsV2.newFunction(), 1);
        vm.stopPrank();
    }

    function testUpgradeTo_RevertWhen_WhenCallerIsNotOwner() public {
        EngenCreditsV2 _implementationV2 = new EngenCreditsV2();

        vm.expectRevert("Ownable: caller is not the owner");
        _engenCredits.upgradeTo(address(_implementationV2));
    }

    /* ============ Set Transfer Enabled tests ============ */

    function testSetTransferEnabled() public {
        assertTrue(!_engenCredits.transfersEnabled());
        vm.prank(_owner);
        _engenCredits.setTransfersEnabled(true);
        assertTrue(_engenCredits.transfersEnabled());
    }

    function testSetTransferEnabled_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        _engenCredits.setTransfersEnabled(true);
    }

    function testSetTransferEnabled_RevertWhen_AlreadyEnabled() public {
        vm.prank(_owner);
        _engenCredits.setTransfersEnabled(true);

        vm.expectRevert("EC: Transfers Already enabled");
        vm.prank(_owner);
        _engenCredits.setTransfersEnabled(true);
    }

    function testSetTransferEnabled_WhenDisabling() public {
        vm.prank(_owner);
        _engenCredits.setTransfersEnabled(false);
        assertEq(_engenCredits.transfersEnabled(), false);
    }

    function testSetTransferEnabled_WhenDisablingAndEnabling() public {
        vm.prank(_owner);
        _engenCredits.setTransfersEnabled(false);
        assertEq(_engenCredits.transfersEnabled(), false);

        vm.prank(_owner);
        _engenCredits.setTransfersEnabled(true);
        assertEq(_engenCredits.transfersEnabled(), true);
    }

    /* ============ Set Burns Enabled tests ============ */

    function testSetBurnsEnabled() public {
        assertTrue(!_engenCredits.burnsEnabled());
        vm.prank(_owner);
        _engenCredits.setBurnsEnabled(true);
        assertTrue(_engenCredits.burnsEnabled());
    }

    function testSetBurnsEnabled_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        _engenCredits.setBurnsEnabled(true);
    }

    function testSetBurnsEnabled_RevertWhen_AlreadyEnabled() public {
        vm.prank(_owner);
        _engenCredits.setBurnsEnabled(true);

        vm.expectRevert("EC: Burns Already enabled");
        vm.prank(_owner);
        _engenCredits.setBurnsEnabled(true);
    }

    function testSetBurnsEnabled_WhenDisabling() public {
        vm.prank(_owner);
        _engenCredits.setBurnsEnabled(false);
        assertEq(_engenCredits.burnsEnabled(), false);
    }

    function testSetBurnsEnabled_WhenDisablingAndEnabling() public {
        vm.prank(_owner);
        _engenCredits.setBurnsEnabled(false);
        assertEq(_engenCredits.burnsEnabled(), false);

        vm.prank(_owner);
        _engenCredits.setBurnsEnabled(true);
        assertEq(_engenCredits.burnsEnabled(), true);
    }

    /* ============ Token tests ============ */

    function testMint() public {
        vm.startPrank(_owner);
        _engenCredits.mint(_user, 100);
        assertEq(_engenCredits.balanceOf(_user), 100);
        vm.stopPrank();
    }

    function testMint_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        _engenCredits.mint(_user, 100);
        assertEq(_engenCredits.balanceOf(_user), 0);
    }

    function testTransfer_RevertWhen_CallerIsAnyone() public {
        vm.startPrank(_owner);
        _engenCredits.mint(_owner, 100);
        vm.expectRevert("EC: Transfers not enabled");
        _engenCredits.transfer(_user2, 100);
        vm.stopPrank();
    }

    function testBurn_RevertWhen_CallerIsAnyone() public {
        vm.startPrank(_owner);
        _engenCredits.mint(_user, 100);
        vm.expectRevert("EC: Transfers not enabled");
        _engenCredits.burn(100);
        vm.stopPrank();
    }

    function testTransfer_WhenTransfersAreEnabled() public {
        vm.startPrank(_owner);

        _engenCredits.mint(_owner, 100);
        _engenCredits.setTransfersEnabled(true);
        _engenCredits.transfer(_user2, 100);

        assertEq(_engenCredits.balanceOf(_user2), 100);
        assertEq(_engenCredits.balanceOf(_owner), 0);

        vm.stopPrank();
    }

    function testBurn_WhenBurnsAreEnabled() public {
        vm.startPrank(_owner);

        _engenCredits.mint(_owner, 100);
        _engenCredits.setBurnsEnabled(true);
        _engenCredits.burn(100);

        assertEq(_engenCredits.balanceOf(_owner), 0);

        vm.stopPrank();
    }

    /* ============ Phase Override tests ============ */

    function testSetPhase1Override() public {
        assertEq(_engenCredits.phase1Override(address(_kintoWallet)), 0);

        uint256[] memory points = new uint256[](1);
        points[0] = 10;
        address[] memory addresses = new address[](1);
        addresses[0] = address(_kintoWallet);

        vm.prank(_owner);
        _engenCredits.setPhase1Override(addresses, points);

        assertEq(_engenCredits.phase1Override(address(_kintoWallet)), 10);
    }

    function testSetPhase1Override_RevertWhen_LengthMismatch() public {
        uint256[] memory points = new uint256[](2);
        points[0] = 10;
        points[1] = 10;

        address[] memory addresses = new address[](1);
        addresses[0] = address(_kintoWallet);

        vm.prank(_owner);
        vm.expectRevert("EC: Invalid input");
        _engenCredits.setPhase1Override(addresses, points);
    }

    /* ============ Mint Credits tests ============ */

    function testMintCredits() public {
        assertEq(_engenCredits.balanceOf(address(_kintoWallet)), 0);
        assertEq(_engenCredits.calculatePoints(address(_kintoWallet)), 15);

        whitelistApp(address(_engenCredits));

        // mint credit
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_engenCredits),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("mintCredits()"),
            address(_paymaster)
        );

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_engenCredits.balanceOf(address(_kintoWallet)), 15);
    }

    function testMintCredits_whenOverride() public {
        whitelistApp(address(_engenCredits));

        // set phase override
        uint256[] memory points = new uint256[](1);
        points[0] = 10;
        address[] memory addresses = new address[](1);
        addresses[0] = address(_kintoWallet);
        vm.prank(_owner);
        _engenCredits.setPhase1Override(addresses, points);

        assertEq(_engenCredits.balanceOf(address(_kintoWallet)), 0);
        assertEq(_engenCredits.calculatePoints(address(_kintoWallet)), 20);

        // mint credits
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_engenCredits),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("mintCredits()"),
            address(_paymaster)
        );
        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_engenCredits.balanceOf(address(_kintoWallet)), 20);
    }

    function testMintCredits_WhenCalledTwice() public {
        whitelistApp(address(_engenCredits));

        assertEq(_engenCredits.balanceOf(address(_kintoWallet)), 0);
        assertEq(_engenCredits.calculatePoints(address(_kintoWallet)), 15);

        // mint creidts
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_engenCredits),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("mintCredits()"),
            address(_paymaster)
        );

        _entryPoint.handleOps(userOps, payable(_owner));
        assertEq(_engenCredits.balanceOf(address(_kintoWallet)), 15);

        // call again
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_engenCredits),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("mintCredits()"),
            address(_paymaster)
        );

        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq("EC: No tokens to mint");

        assertEq(_engenCredits.balanceOf(address(_kintoWallet)), 15);
    }

    function testMintCredits_RevertWhen_TransfersEnabled() public {
        whitelistApp(address(_engenCredits));

        vm.prank(_owner);
        _engenCredits.setTransfersEnabled(true);

        // mint credit
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_engenCredits),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("mintCredits()"),
            address(_paymaster)
        );

        vm.expectEmit(true, true, true, false);
        uint256 last = userOps.length - 1;
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq("EC: Mint not allowed after completion");
    }

    function testMintCredits_RevertWhen_BurnsEnabled() public {
        whitelistApp(address(_engenCredits));

        vm.prank(_owner);
        _engenCredits.setBurnsEnabled(true);

        // mint credit
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            address(_kintoWallet),
            address(_engenCredits),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("mintCredits()"),
            address(_paymaster)
        );

        vm.expectEmit(true, true, true, false);
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq("EC: Mint not allowed after completion");
    }
}

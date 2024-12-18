// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core/tokens/EngenCredits.sol";
import "@kinto-core/interfaces/IEngenCredits.sol";

import "@kinto-core-test/SharedSetup.t.sol";

contract EngenCreditsUpgrade is EngenCredits {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor() EngenCredits() {}
}

contract EngenCreditsTest is SharedSetup {
    function setUp() public override {
        super.setUp();
        fundSponsorForApp(_owner, address(_engenCredits));
        registerApp(address(_kintoWallet), "engen credits", address(_engenCredits), new address[](0));
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
        EngenCreditsUpgrade _implementation = new EngenCreditsUpgrade();
        _engenCredits.upgradeTo(address(_implementation));

        // ensure that the implementation has been upgraded
        EngenCreditsUpgrade _EngenCreditsUpgrade = EngenCreditsUpgrade(address(_engenCredits));
        assertEq(_EngenCreditsUpgrade.newFunction(), 1);
        vm.stopPrank();
    }

    function testUpgradeTo_RevertWhen_WhenCallerIsNotOwner() public {
        EngenCreditsUpgrade _implementation = new EngenCreditsUpgrade();

        vm.expectRevert("Ownable: caller is not the owner");
        _engenCredits.upgradeTo(address(_implementation));
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

        vm.expectRevert(IEngenCredits.TransfersAlreadyEnabled.selector);
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

        vm.expectRevert(IEngenCredits.BurnsAlreadyEnabled.selector);
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
        vm.expectRevert(IEngenCredits.TransfersNotEnabled.selector);
        _engenCredits.transfer(_user2, 100);
        vm.stopPrank();
    }

    function testBurn_RevertWhen_CallerIsAnyone() public {
        vm.startPrank(_owner);
        _engenCredits.mint(_owner, 100);
        vm.expectRevert(IEngenCredits.TransfersNotEnabled.selector);
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

    function testSetEarnedCredits() public {
        assertEq(_engenCredits.earnedCredits(address(_kintoWallet)), 0);

        uint256[] memory points = new uint256[](1);
        points[0] = 10;
        address[] memory addresses = new address[](1);
        addresses[0] = address(_kintoWallet);

        vm.prank(_owner);
        _engenCredits.setCredits(addresses, points);

        assertEq(_engenCredits.earnedCredits(address(_kintoWallet)), 10);
    }

    function testSetEarnedCredits_RevertWhen_LengthMismatch() public {
        uint256[] memory points = new uint256[](2);
        points[0] = 10;
        points[1] = 10;

        address[] memory addresses = new address[](1);
        addresses[0] = address(_kintoWallet);

        vm.prank(_owner);
        vm.expectRevert(IEngenCredits.LengthMismatch.selector);
        _engenCredits.setCredits(addresses, points);
    }

    /* ============ Mint Credits tests ============ */

    function testMintCredits() public {
        assertEq(_engenCredits.balanceOf(address(_kintoWallet)), 0);

        whitelistApp(address(_engenCredits));

        // set points
        uint256[] memory points = new uint256[](1);
        points[0] = 10;
        address[] memory addresses = new address[](1);
        addresses[0] = address(_kintoWallet);
        vm.prank(_owner);
        _engenCredits.setCredits(addresses, points);

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
        assertEq(_engenCredits.balanceOf(address(_kintoWallet)), 10);
    }

    function testMintCredits_whenOverride() public {
        whitelistApp(address(_engenCredits));

        // set points
        uint256[] memory points = new uint256[](1);
        points[0] = 10;
        address[] memory addresses = new address[](1);
        addresses[0] = address(_kintoWallet);
        vm.prank(_owner);
        _engenCredits.setCredits(addresses, points);

        assertEq(_engenCredits.balanceOf(address(_kintoWallet)), 0);
        assertEq(_engenCredits.earnedCredits(address(_kintoWallet)), 10);

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
        assertEq(_engenCredits.balanceOf(address(_kintoWallet)), 10);
    }

    function testMintCredits_WhenCalledTwice() public {
        whitelistApp(address(_engenCredits));

        assertEq(_engenCredits.balanceOf(address(_kintoWallet)), 0);
        assertEq(_engenCredits.earnedCredits(address(_kintoWallet)), 0);

        vm.prank(_owner);
        uint256[] memory points = new uint256[](1);
        points[0] = 15;
        address[] memory addresses = new address[](1);
        addresses[0] = address(_kintoWallet);
        _engenCredits.setCredits(addresses, points);

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
        assertRevertReasonEq(IEngenCredits.NoTokensToMint.selector);

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
        emit UserOperationRevertReason(
            _entryPoint.getUserOpHash(userOps[0]), userOps[0].sender, userOps[0].nonce, bytes("")
        );
        vm.recordLogs();
        _entryPoint.handleOps(userOps, payable(_owner));
        assertRevertReasonEq(IEngenCredits.MintNotAllowed.selector);
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
        assertRevertReasonEq(IEngenCredits.MintNotAllowed.selector);
    }
}

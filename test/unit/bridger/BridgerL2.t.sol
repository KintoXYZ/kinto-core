// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/interfaces/bridger/IBridger.sol";
import "@kinto-core/bridger/BridgerL2.sol";

import "@kinto-core-test/helpers/UUPSProxy.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/SharedSetup.t.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BridgerL2NewUpgrade is BridgerL2 {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(address factory) BridgerL2(factory) {}
}

contract BridgerL2Test is SignatureHelper, SharedSetup {
    address sDAI = 0x4190A8ABDe37c9A85fAC181037844615BA934711; // virtual sDAI
    address sDAIL2 = 0x5da1004F7341D510C6651C67B4EFcEEA76Cac0E8; // sDAI L2 representation

    function setUp() public override {
        super.setUp();

        // add a token implementation to the real sDAI L2 representation address
        ERC20 token = new ERC20("Test", "TST");
        vm.etch(sDAIL2, address(token).code);

        fundSponsorForApp(_owner, address(_bridgerL2));
        registerApp(address(_kintoWallet), "bridger", address(_bridgerL2), new address[](0));
    }

    function testUp() public view override {
        assertEq(_bridgerL2.owner(), address(_owner));
        assertEq(_bridgerL2.depositCount(), 0);
        assertEq(_bridgerL2.unlocked(), false);
    }

    /* ============ Upgrade tests ============ */

    function testUpgradeTo() public {
        BridgerL2NewUpgrade _newImpl = new BridgerL2NewUpgrade(address(_walletFactory));
        vm.prank(_owner);
        _bridgerL2.upgradeTo(address(_newImpl));
        assertEq(BridgerL2NewUpgrade(payable(address(_bridgerL2))).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner() public {
        BridgerL2NewUpgrade _newImpl = new BridgerL2NewUpgrade(address(_walletFactory));
        vm.expectRevert("Ownable: caller is not the owner");
        _bridgerL2.upgradeToAndCall(address(_newImpl), bytes(""));
    }

    /* ============ Write L2 Deposit ============ */

    function testWriteL2Deposit() public {
        address _asset = sDAI;
        uint256 _amount = 100;

        uint256 depositsBefore = _bridgerL2.deposits(address(_kintoWallet), _asset);
        uint256 depositTotalsBefore = _bridgerL2.depositTotals(_asset);
        uint256 depositCountBefore = _bridgerL2.depositCount();

        vm.prank(_owner);
        _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);

        assertEq(_bridgerL2.deposits(address(_kintoWallet), _asset), depositsBefore + _amount);
        assertEq(_bridgerL2.depositTotals(_asset), depositTotalsBefore + _amount);
        assertEq(_bridgerL2.depositCount(), depositCountBefore + 1);
    }

    function testWriteL2Deposit_WhenMultipleCalls() public {
        address _asset = sDAI;
        uint256 _amount = 100;

        uint256 depositsBefore = _bridgerL2.deposits(address(_kintoWallet), _asset);
        uint256 depositTotalsBefore = _bridgerL2.depositTotals(_asset);
        uint256 depositCountBefore = _bridgerL2.depositCount();

        vm.startPrank(_owner);
        _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);
        _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);
        vm.stopPrank();

        assertEq(_bridgerL2.deposits(address(_kintoWallet), _asset), depositsBefore + _amount * 2);
        assertEq(_bridgerL2.depositTotals(_asset), depositTotalsBefore + _amount * 2);
        assertEq(_bridgerL2.depositCount(), depositCountBefore + 2);
    }

    function testWriteL2Deposit_RevertWhen_CallerIsNotOwner() public {
        address _asset = sDAI;
        uint256 _amount = 100;
        vm.expectRevert(IBridgerL2.Unauthorized.selector);
        _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);
    }

    /* ============ Unlock Commitments ============ */

    function testUnlockCommitments() public {
        vm.prank(_owner);
        _bridgerL2.unlockCommitments();
        assertEq(_bridgerL2.unlocked(), true);
    }

    function testUnlockCommitments_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        _bridgerL2.unlockCommitments();
    }

    /* ============ SetDeposited Assets ============ */

    function testSetDepositedAssets() public {
        address[] memory _assets = new address[](2);
        _assets[0] = sDAI;
        _assets[1] = address(0x46);

        vm.prank(_owner);
        _bridgerL2.setDepositedAssets(_assets);

        assertEq(_bridgerL2.depositedAssets(0), sDAI);
        assertEq(_bridgerL2.depositedAssets(1), address(0x46));
    }

    function testSetDepositedAssets_RevertWhen_CallerIsNotOwner() public {
        address[] memory _assets = new address[](2);
        _assets[0] = address(0x45);
        _assets[1] = address(0x46);

        vm.expectRevert("Ownable: caller is not the owner");
        _bridgerL2.setDepositedAssets(_assets);
    }

    /* ============ Claim Commitment ============ */

    function testClaimCommitment() public {
        address _asset = sDAI;
        uint256 _amount = 100;

        address[] memory _assets = new address[](1);
        _assets[0] = _asset;
        deal(sDAIL2, address(_bridgerL2), _amount);

        vm.startPrank(_owner);

        _bridgerL2.setDepositedAssets(_assets);
        _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);
        _bridgerL2.unlockCommitments();

        vm.stopPrank();

        vm.prank(address(_kintoWallet));
        _bridgerL2.claimCommitment();

        assertEq(_bridgerL2.deposits(address(_kintoWallet), _asset), 0);
        assertEq(ERC20(sDAIL2).balanceOf(address(_kintoWallet)), _amount);
    }

    function testClaimCommitment_RevertWhen_WalletIsInvalid() public {
        address _asset = sDAI;
        uint256 _amount = 100;

        address[] memory _assets = new address[](1);
        _assets[0] = _asset;
        deal(sDAIL2, address(_bridgerL2), _amount);

        vm.startPrank(_owner);

        _bridgerL2.setDepositedAssets(_assets);
        _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);
        _bridgerL2.unlockCommitments();

        vm.stopPrank();

        vm.prank(_user);
        vm.expectRevert(IBridgerL2.InvalidWallet.selector);
        _bridgerL2.claimCommitment();
    }

    function testClaimCommitment_RevertWhen_NotUnlocked() public {
        address _asset = sDAI;
        uint256 _amount = 100;

        address[] memory _assets = new address[](1);
        _assets[0] = _asset;
        deal(sDAIL2, address(_bridgerL2), _amount);

        vm.startPrank(_owner);

        _bridgerL2.setDepositedAssets(_assets);
        _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);

        vm.stopPrank();

        vm.prank(address(_kintoWallet));
        vm.expectRevert(IBridgerL2.NotUnlockedYet.selector);
        _bridgerL2.claimCommitment();
    }

    /* ============ Viewers ============ */

    function testGetUserDeposits() public {
        address[] memory _assets = new address[](2);
        _assets[0] = address(1);
        _assets[1] = address(2);

        vm.startPrank(_owner);

        _bridgerL2.setDepositedAssets(_assets);
        _bridgerL2.writeL2Deposit(address(1), _assets[0], 1 ether);
        _bridgerL2.writeL2Deposit(address(1), _assets[1], 2 ether);
        _bridgerL2.writeL2Deposit(address(2), _assets[1], 2 ether);

        vm.stopPrank();

        uint256[] memory amounts = _bridgerL2.getUserDeposits(address(1));
        assertEq(amounts[0], 1 ether);
        assertEq(amounts[1], 2 ether);

        amounts = _bridgerL2.getUserDeposits(address(2));
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 2 ether);
    }

    function testGetTotalDeposits() public {
        address[] memory _assets = new address[](2);
        _assets[0] = address(1);
        _assets[1] = address(2);

        vm.startPrank(_owner);

        _bridgerL2.setDepositedAssets(_assets);
        _bridgerL2.writeL2Deposit(address(1), _assets[0], 1 ether);
        _bridgerL2.writeL2Deposit(address(1), _assets[1], 2 ether);
        _bridgerL2.writeL2Deposit(address(2), _assets[1], 2 ether);

        vm.stopPrank();

        uint256[] memory amounts = _bridgerL2.getTotalDeposits();
        assertEq(amounts[0], 1 ether);
        assertEq(amounts[1], 4 ether);
    }

    // todo: test everything through user ops because it is what we will use
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/interfaces/bridger/IBridger.sol";
import "@kinto-core/bridger/BridgerL2.sol";

import "@kinto-core-test/helpers/ArrayHelpers.sol";
import "@kinto-core-test/helpers/UUPSProxy.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/SharedSetup.t.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BridgerL2NewUpgrade is BridgerL2 {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(address factory, address kintoID) BridgerL2(factory, kintoID) {}
}

contract BridgerL2Test is SignatureHelper, SharedSetup {
    using ArrayHelpers for *;

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
        BridgerL2NewUpgrade _newImpl = new BridgerL2NewUpgrade(address(_walletFactory), address(_kintoID));
        vm.prank(_owner);
        _bridgerL2.upgradeTo(address(_newImpl));
        assertEq(BridgerL2NewUpgrade(payable(address(_bridgerL2))).newFunction(), 1);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner() public {
        BridgerL2NewUpgrade _newImpl = new BridgerL2NewUpgrade(address(_walletFactory), address(_kintoID));
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

    /* ============ WithdrawERC20 ============ */

    function testWithdrawERC20_RevertWhen_NotWallet() public {
        address token = address(new ERC20("Test", "TST"));
        IBridger.BridgeData memory bridgeData;

        vm.expectRevert(abi.encodeWithSelector(IBridgerL2.InvalidWallet.selector, address(this)));
        _bridgerL2.withdrawERC20(token, 1 ether, _owner, 0, bridgeData);
    }

    function testWithdrawERC20_RevertWhen_NotKYCd() public {
        address token = address(new ERC20("Test", "TST"));
        IBridger.BridgeData memory bridgeData;

        // Revoke KYC
        vm.prank(_kycProvider);
        KintoID(_kintoID).addSanction(_owner, 1);

        vm.prank(address(_kintoWallet));
        vm.expectRevert(abi.encodeWithSelector(IBridgerL2.KYCRequired.selector, _owner));
        _bridgerL2.withdrawERC20(token, 1 ether, _owner, 0, bridgeData);
    }

    function testWithdrawERC20_RevertWhen_InvalidReceiver() public {
        address token = address(new ERC20("Test", "TST"));
        address invalidReceiver = address(0xbad);
        IBridger.BridgeData memory bridgeData;

        vm.prank(address(_kintoWallet));
        vm.expectRevert(abi.encodeWithSelector(IBridgerL2.InvalidReceiver.selector, invalidReceiver));
        _bridgerL2.withdrawERC20(token, 1 ether, invalidReceiver, 0, bridgeData);
    }

    /* ============ Allowlists ============ */

    function testSetReceiverAllowlist() public {
        address receiver1 = address(0x1);
        address receiver2 = address(0x2);

        vm.prank(_owner);
        vm.expectEmit(true, true, true, true);
        emit IBridgerL2.ReceiverSet([receiver1, receiver2].toMemoryArray(), [true, false].toMemoryArray());
        _bridgerL2.setReceiver([receiver1, receiver2].toMemoryArray(), [true, false].toMemoryArray());

        address[] memory allowedReceivers = _bridgerL2.receiveAllowlist();
        assertEq(allowedReceivers.length, 1);
        assertEq(allowedReceivers[0], receiver1);
    }

    function testSetSenderAllowlist() public {
        address sender1 = address(0x1);
        address sender2 = address(0x2);

        vm.prank(_owner);
        vm.expectEmit(true, true, true, true);
        emit IBridgerL2.SenderSet([sender1, sender2].toMemoryArray(), [true, false].toMemoryArray());
        _bridgerL2.setSender([sender1, sender2].toMemoryArray(), [true, false].toMemoryArray());

        address[] memory allowedSenders = _bridgerL2.senderAllowlist();
        assertEq(allowedSenders.length, 1);
        assertEq(allowedSenders[0], sender1);
    }

    function testSetReceiver_RevertWhen_NotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        _bridgerL2.setReceiver([address(0x1)].toMemoryArray(), [true].toMemoryArray());
    }

    function testSetSender_RevertWhen_NotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        _bridgerL2.setSender([address(0x1)].toMemoryArray(), [true].toMemoryArray());
    }

    /* ============ SetBridgeVault ============ */

    function testSetBridgeVault() public {
        address vault1 = address(0x1);
        address vault2 = address(0x2);

        vm.prank(_owner);
        vm.expectEmit(true, true, true, true);
        emit IBridgerL2.BridgeVaultSet([vault1, vault2].toMemoryArray(), [true, false].toMemoryArray());
        _bridgerL2.setBridgeVault([vault1, vault2].toMemoryArray(), [true, false].toMemoryArray());

        address[] memory registeredVaults = _bridgerL2.bridgeVaults();
        assertEq(registeredVaults.length, 1);
        assertEq(registeredVaults[0], vault1);
    }

    function testSetBridgeVault_RevertWhen_NotOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        _bridgerL2.setBridgeVault([address(0x1)].toMemoryArray(), [true].toMemoryArray());
    }

    /* ============ Hooks ============ */

    function testSrcPreHookCall() external view {
        _bridgerL2.srcPreHookCall(
            SrcPreHookCallParams(address(0), address(_kintoWallet), TransferInfo(address(0), 0, bytes("")))
        );
    }

    function testSrcPreHookCall__WhenSenderBridgerL2() external view {
        address receiver = address(_kintoWallet);

        _bridgerL2.srcPreHookCall(
            SrcPreHookCallParams(address(0), address(_bridgerL2), TransferInfo(receiver, 0, bytes("")))
        );
    }

    function testSrcPreHookCall__SenderNotKYCd() external {
        // revoke KYC to sender
        vm.prank(_kycProvider);
        KintoID(_kintoID).addSanction(_owner, 1);

        vm.expectRevert(abi.encodeWithSelector(IBridgerL2.KYCRequired.selector, _kintoWallet));
        _bridgerL2.srcPreHookCall(
            SrcPreHookCallParams(address(0), address(_kintoWallet), TransferInfo(address(0), 0, bytes("")))
        );
    }

    function testDstPreHookCall__ReceiverNotKintoWallet() external {
        address sender = _owner;
        address receiver = address(0xdead);

        vm.expectRevert(abi.encodeWithSelector(IBridgerL2.InvalidReceiver.selector, receiver));
        _bridgerL2.dstPreHookCall(
            DstPreHookCallParams(address(0), bytes(""), TransferInfo(receiver, 0, abi.encode(sender)))
        );
    }

    function testDstPreHookCall__ReceiverNotKYCd() external {
        // revoke KYC to receiver
        vm.prank(_kycProvider);
        KintoID(_kintoID).addSanction(_owner, 1);

        vm.expectRevert(abi.encodeWithSelector(IBridgerL2.KYCRequired.selector, _kintoWallet));
        _bridgerL2.dstPreHookCall(
            DstPreHookCallParams(address(0), bytes(""), TransferInfo(address(_kintoWallet), 0, abi.encode(_owner)))
        );
    }

    function testDstPreHookCall__SenderNotAllowed() external {
        address sender = address(0xdead);

        vm.expectRevert(abi.encodeWithSelector(IBridgerL2.SenderNotAllowed.selector, sender));
        _bridgerL2.dstPreHookCall(
            DstPreHookCallParams(address(0), bytes(""), TransferInfo(address(_kintoWallet), 0, abi.encode(sender)))
        );
    }

    function testDstPreHookCallCall__WhenReceiverIsInAllowlist() external {
        address sender = _owner;
        address receiver = address(_kintoWallet);

        // revoke KYC to receiver
        vm.prank(_kycProvider);
        KintoID(_kintoID).addSanction(_owner, 1);

        vm.prank(_bridgerL2.owner());
        _bridgerL2.setReceiver([receiver].toMemoryArray(), [true].toMemoryArray());

        _bridgerL2.dstPreHookCall(
            DstPreHookCallParams(address(0), bytes(""), TransferInfo(receiver, 0, abi.encode(sender)))
        );
    }

    function testDstPreHookCallCall__WhenSenderIsInAllowlist() external {
        address sender = address(0xdead);

        vm.prank(_bridgerL2.owner());
        _bridgerL2.setSender([sender].toMemoryArray(), [true].toMemoryArray());

        vm.prank(_bridgerL2.owner());
        _bridgerL2.dstPreHookCall(
            DstPreHookCallParams(address(0), bytes(""), TransferInfo(address(_kintoWallet), 0, abi.encode(sender)))
        );
    }

    function testDstPreHookCallCall__WhenSenderIsKintoWalletSigner() external view {
        _bridgerL2.dstPreHookCall(
            DstPreHookCallParams(address(0), bytes(""), TransferInfo(address(_kintoWallet), 0, abi.encode(_owner)))
        );
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
}

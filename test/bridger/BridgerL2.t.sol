// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/interfaces/IBridger.sol";
import "../../src/bridger/BridgerL2.sol";

import "../helpers/UUPSProxy.sol";
import "../helpers/TestSignature.sol";
import "../helpers/TestSignature.sol";
import "../SharedSetup.t.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BridgerL2NewUpgrade is BridgerL2 {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(address factory) BridgerL2(factory) {}
}

contract BridgerL2Test is TestSignature, SharedSetup {
    ERC20 public _token;

    function setUp() public override {
        super.setUp();
        _token = new ERC20("Test", "TST");
        fundSponsorForApp(_owner, address(_bridgerL2));
        registerApp(_owner, "bridger", address(_bridgerL2));
    }

    function testUp() public override {
        assertEq(_bridgerL2.depositCount(), 0);
        assertEq(_bridgerL2.owner(), address(_owner));
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
        vm.expectRevert(IBridgerL2.OnlyOwner.selector);
        _bridgerL2.upgradeToAndCall(address(_newImpl), bytes(""));
    }

    /* ============ Write L2 Deposit ============ */

    function testWriteL2Deposit() public {
        address _asset = address(_token);
        uint256 _amount = 100;
        vm.prank(_owner);
        _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);
        assertEq(_bridgerL2.deposits(address(_kintoWallet), _asset), _amount);
        assertEq(_bridgerL2.depositTotals(_asset), _amount);
        assertEq(_bridgerL2.depositCount(), 1);
    }

    function testWriteL2Deposit_WhenMultipleCalls() public {
        address _asset = address(_token);
        uint256 _amount = 100;
        vm.startPrank(_owner);
        _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);
        _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);
        assertEq(_bridgerL2.deposits(address(_kintoWallet), _asset), _amount * 2);
        assertEq(_bridgerL2.depositTotals(_asset), _amount * 2);
        assertEq(_bridgerL2.depositCount(), 2);
        vm.stopPrank();
    }

    function testWriteL2Deposit_RevertWhen_CallerIsNotOwner() public {
        address _asset = address(_token);
        uint256 _amount = 100;
        vm.expectRevert(IBridgerL2.OnlyOwner.selector);
        _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);
    }

    /* ============ Unlock Commitments ============ */

    function testUnlockCommitments() public {
        vm.prank(_owner);
        _bridgerL2.unlockCommitments();
        assertEq(_bridgerL2.unlocked(), true);
    }

    function testUnlockCommitments_RevertWhen_CallerIsNotOwner() public {
        vm.expectRevert(IBridgerL2.OnlyOwner.selector);
        _bridgerL2.unlockCommitments();
    }

    /* ============ SetDeposited Assets ============ */

    function testSetDepositedAssets() public {
        vm.startPrank(_owner);
        address[] memory _assets = new address[](2);
        _assets[0] = address(_token);
        _assets[1] = address(0x46);
        _bridgerL2.setDepositedAssets(_assets);
        assertEq(_bridgerL2.depositedAssets(0), address(_token));
        assertEq(_bridgerL2.depositedAssets(1), address(0x46));
    }

    function testSetDepositedAssets_RevertWhen_CallerIsNotOwner() public {
        address[] memory _assets = new address[](2);
        _assets[0] = address(0x45);
        _assets[1] = address(0x46);
        vm.expectRevert(IBridgerL2.OnlyOwner.selector);
        _bridgerL2.setDepositedAssets(_assets);
    }

    /* ============ Claim Commitment ============ */

    function testClaimCommitment() public {
        address _asset = address(_token);
        uint256 _amount = 100;
        vm.startPrank(_owner);
        address[] memory _assets = new address[](1);
        _assets[0] = _asset;
        deal(_asset, address(_bridgerL2), _amount);
        _bridgerL2.setDepositedAssets(_assets);
        _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);
        _bridgerL2.unlockCommitments();
        vm.stopPrank();
        vm.prank(address(_kintoWallet));
        _bridgerL2.claimCommitment();
        assertEq(_bridgerL2.deposits(address(_kintoWallet), _asset), 0);
        assertEq(ERC20(_asset).balanceOf(address(_kintoWallet)), _amount);
    }

    function testClaimCommitment_RevertWhen_WalletIsInvalid() public {
        address _asset = address(_token);
        uint256 _amount = 100;
        vm.startPrank(_owner);
        address[] memory _assets = new address[](1);
        _assets[0] = _asset;
        deal(_asset, address(_bridgerL2), _amount);
        _bridgerL2.setDepositedAssets(_assets);
        _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);
        _bridgerL2.unlockCommitments();
        vm.stopPrank();
        vm.prank(_user);
        vm.expectRevert(IBridgerL2.InvalidWallet.selector);
        _bridgerL2.claimCommitment();
    }

    function testClaimCommitment_RevertWhen_NotUnlocked() public {
        address _asset = address(_token);
        uint256 _amount = 100;
        vm.startPrank(_owner);
        address[] memory _assets = new address[](1);
        _assets[0] = _asset;
        deal(_asset, address(_bridgerL2), _amount);
        _bridgerL2.setDepositedAssets(_assets);
        _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);
        vm.stopPrank();
        vm.prank(address(_kintoWallet));
        vm.expectRevert(IBridgerL2.NotUnlockedYet.selector);
        _bridgerL2.claimCommitment();
    }
}

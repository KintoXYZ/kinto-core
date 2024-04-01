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

        if (fork) {
            // transfer owner's ownership to _owner
            vm.prank(_bridgerL2.owner());
            _bridgerL2.transferOwnership(_owner);
        }

        fundSponsorForApp(_owner, address(_bridgerL2));
        registerApp(_owner, "bridger", address(_bridgerL2));
    }

    function testUp() public override {
        assertEq(_bridgerL2.owner(), address(_owner));
        if (fork) return;
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
        address _asset = address(_token);
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
        address _asset = address(_token);
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
        address _asset = address(_token);
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
        vm.expectRevert("Ownable: caller is not the owner");
        _bridgerL2.setDepositedAssets(_assets);
    }

    /* ============ Claim Commitment ============ */

    function testClaimCommitment() public {
        address _asset = address(_token);
        uint256 _amount = 100;

        address[] memory _assets = new address[](1);
        _assets[0] = _asset;
        deal(_asset, address(_bridgerL2), _amount);

        vm.startPrank(_owner);

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

    /* ============ Claim Commitment (with real asset) ============ */

    function testClaimCommitment_WhenRealAsset() public {
        if (!fork) return;

        // upgrade Bridger L2 to latest version
        // TODO: remove upgrade after having actually upgraded the contract on mainnet
        BridgerL2 _newImpl = new BridgerL2(address(_walletFactory));
        vm.prank(_owner);
        _bridgerL2.upgradeTo(address(_newImpl));

        // UI "wrong" assets
        address[] memory UI_assets = new address[](4);
        UI_assets[0] = 0x4190A8ABDe37c9A85fAC181037844615BA934711; // sDAI
        UI_assets[1] = 0xF4d81A46cc3fCA44f88d87912A35E7fCC4B398ee; // sUSDe
        UI_assets[2] = 0x6e316425A25D2Cf15fb04BCD3eE7c6325B240200; // wstETH
        UI_assets[3] = 0xC60F14d95B87417BfD17a376276DE15bE7171d31; // weETH

        // L2 representations
        address[] memory L2_assets = new address[](4);
        L2_assets[0] = 0x71E742F94362097D67D1e9086cE4604256EEDd25; // sDAI
        L2_assets[1] = 0xa75C0f526578595AdB75D13FCea1017AC1b97e48; // sUSDe
        L2_assets[2] = 0xCA47413347D04E0ce1843824C736740f787845e5; // wstETH
        L2_assets[3] = 0x578395611F459F615D877447Dcc955d7095504cb; // weETH

        for (uint256 i = 0; i < 4; i++) {
            address _asset = UI_assets[i];
            uint256 _amount = 100;

            address[] memory _assets = new address[](1);
            _assets[0] = _asset;

            vm.startPrank(_owner);

            _bridgerL2.setDepositedAssets(_assets);
            _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);
            _bridgerL2.unlockCommitments();

            vm.stopPrank();

            // add balance of the real asset representation to the bridger
            deal(L2_assets[i], address(_bridgerL2), _amount);

            vm.prank(address(_kintoWallet));
            _bridgerL2.claimCommitment();

            assertEq(_bridgerL2.deposits(address(_kintoWallet), _asset), 0);
            assertEq(ERC20(L2_assets[i]).balanceOf(address(_kintoWallet)), _amount);
        }
    }

    // todo: test everything through user ops because it is what we will use
}

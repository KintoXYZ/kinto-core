// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {stdJson} from "forge-std/StdJson.sol";
import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";
import {IBridge} from "@kinto-core/interfaces/bridger/IBridge.sol";
import {BridgerL2} from "@kinto-core/bridger/BridgerL2.sol";

import {SignatureHelper} from "@kinto-core-test/helpers/SignatureHelper.sol";
import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";
import {BridgeDataHelper} from "@kinto-core-test/helpers/BridgeDataHelper.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@kinto-core-test/helpers/ArrayHelpers.sol";

import "forge-std/console2.sol";

contract BridgerL2Test is SignatureHelper, SharedSetup, BridgeDataHelper {
    using ArrayHelpers for *;
    using stdJson for string;

    mapping(address => uint256) internal balancesBefore;
    address ENA = 0xE040001C257237839a69E9683349C173297876F0;

    function setUp() public override {
        super.setUp();
        // transfer owner's ownership to _owner
        vm.prank(_bridgerL2.owner());
        _bridgerL2.transferOwnership(_owner);

        // upgrade Bridger L2 to latest version
        // TODO: remove upgrade after having actually upgraded the contract on mainnet
        BridgerL2 _newImpl = new BridgerL2(address(_walletFactory), address(_kintoID));
        vm.prank(_owner);
        _bridgerL2.upgradeTo(address(_newImpl));
    }

    function setUpChain() public virtual override {
        setUpKintoFork();
    }

    /* ============ Withdraw  ============ */

    function testWithdrawERC20() public {
        address inputAsset = DAI_KINTO;
        uint256 amountIn = 1e17;
        uint256 fee = 1;

        IBridger.BridgeData memory bridgeData = bridgeData[block.chainid][DAI_KINTO];

        deal(inputAsset, address(_kintoWallet), amountIn + fee);

        vm.prank(_bridgerL2.owner());
        _bridgerL2.setBridgeVault([bridgeData.vault].toMemoryArray(), [true].toMemoryArray());

        vm.prank(address(_kintoWallet));
        IERC20(inputAsset).approve(address(_bridgerL2), amountIn + fee);

        bridgeData.gasFee = IBridge(bridgeData.vault).getMinFees(bridgeData.connector, bridgeData.msgGasLimit, 322);
        deal(address(_bridgerL2), bridgeData.gasFee);

        vm.startPrank(address(_kintoWallet));
        _bridgerL2.withdrawERC20(inputAsset, amountIn, _kintoWallet.owners(0), fee, bridgeData);
        vm.stopPrank();
    }

    /* ============ Claim Commitment (with real asset) ============ */

    function testClaimCommitment_WhenRealAsset() public {
        // UI "wrong" assets
        address[] memory UI_assets = new address[](4);
        UI_assets[0] = 0x4190A8ABDe37c9A85fAC181037844615BA934711; // sDAI
        UI_assets[1] = 0xF4d81A46cc3fCA44f88d87912A35E7fCC4B398ee; // sUSDe
        UI_assets[2] = 0x6e316425A25D2Cf15fb04BCD3eE7c6325B240200; // wstETH
        UI_assets[3] = 0xC60F14d95B87417BfD17a376276DE15bE7171d31; // weETH

        // L2 representations
        address[] memory L2_assets = new address[](4);
        L2_assets[0] = 0x5da1004F7341D510C6651C67B4EFcEEA76Cac0E8; // sDAI
        L2_assets[1] = 0x505de0f7a5d786063348aB5BC31e3a21344fA7B0; // sUSDe
        L2_assets[2] = 0x057e70cCa0dC435786a50FcF440bf8FcC1eEAf17; // wstETH
        L2_assets[3] = 0x0Ee700095AeDFe0814fFf7d6DFD75461De8e2b19; // weETH

        // unlock commitments
        vm.prank(_owner);
        _bridgerL2.unlockCommitments();

        // set deposited assets
        address[] memory assets = new address[](5);
        assets[0] = UI_assets[0];
        assets[1] = UI_assets[1];
        assets[2] = UI_assets[2];
        assets[3] = UI_assets[3];
        assets[4] = ENA;

        vm.prank(_owner);
        _bridgerL2.setDepositedAssets(assets);

        uint256 balanceBefore;
        for (uint256 i = 0; i < 4; i++) {
            address _asset = UI_assets[i];
            uint256 _amount = 100;
            balanceBefore = ERC20(L2_assets[i]).balanceOf(address(_kintoWallet));

            address[] memory _assets = new address[](1);
            _assets[0] = _asset;

            vm.startPrank(_owner);

            _bridgerL2.writeL2Deposit(address(_kintoWallet), _asset, _amount);

            vm.stopPrank();

            // add balance of the real asset representation to the bridger
            deal(L2_assets[i], address(_bridgerL2), _amount);

            vm.prank(address(_kintoWallet));
            _bridgerL2.claimCommitment();

            assertEq(_bridgerL2.deposits(address(_kintoWallet), _asset), 0);
            assertEq(ERC20(L2_assets[i]).balanceOf(address(_kintoWallet)), balanceBefore + _amount);
        }

        // assign ENA rewards
        balanceBefore = ERC20(ENA).balanceOf(address(_kintoWallet));
        address[] memory users = new address[](1);
        users[0] = address(_kintoWallet);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100;

        vm.prank(_owner);
        _bridgerL2.assignENARewards(users, amounts);

        // add ENA balance to the bridger
        deal(ENA, address(_bridgerL2), 100);

        // claim ENA rewards
        vm.prank(address(_kintoWallet));
        _bridgerL2.claimCommitment();

        assertEq(_bridgerL2.deposits(address(_kintoWallet), ENA), 0);
        assertEq(ERC20(ENA).balanceOf(address(_kintoWallet)), balanceBefore + 100);
    }

    function testAssignWstEthRefunds() public {
        address wstEthFake = 0x6e316425A25D2Cf15fb04BCD3eE7c6325B240200;
        address wstEthReal = 0x057e70cCa0dC435786a50FcF440bf8FcC1eEAf17;

        // assign wstEthRefunds
        uint256 balanceBefore = ERC20(wstEthReal).balanceOf(address(_kintoWallet));
        address[] memory users = new address[](1);
        users[0] = address(_kintoWallet);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;

        vm.prank(_owner);
        _bridgerL2.assignWstEthRefunds(users, amounts);

        deal(wstEthReal, address(_bridgerL2), 1e18);

        vm.prank(_bridgerL2.owner());
        _bridgerL2.unlockCommitments();

        vm.prank(address(_kintoWallet));
        _bridgerL2.claimCommitment();

        assertEq(_bridgerL2.deposits(address(_kintoWallet), wstEthFake), 0);
        assertEq(ERC20(wstEthReal).balanceOf(address(_kintoWallet)), balanceBefore + 1e18);
    }

    function testAssignWstEthRefundsAll() public {
        // takes a lot of time
        vm.skip(true);
        address wstEthFake = 0x6e316425A25D2Cf15fb04BCD3eE7c6325B240200;

        string memory json = vm.readFile("./script/data/wstETHgasUsed.json");
        string[] memory keys = vm.parseJsonKeys(json, "$");
        address[] memory users = new address[](keys.length);
        uint256[] memory amounts = new uint256[](keys.length);
        for (uint256 index = 0; index < keys.length; index++) {
            uint256 amount = json.readUint(string.concat(".", keys[index]));
            address user = vm.parseAddress(keys[index]);
            users[index] = user;
            amounts[index] = amount;
            balancesBefore[user] = _bridgerL2.deposits(user, wstEthFake);
        }

        // assign wstEthRefunds
        vm.prank(_owner);
        _bridgerL2.assignWstEthRefunds(users, amounts);

        for (uint256 index = 0; index < keys.length; index++) {
            address user = users[index];
            uint256 amount = amounts[index];
            assertEq(_bridgerL2.deposits(user, wstEthFake), balancesBefore[user] + amount, "Balance is wrong");
        }
    }

    function testAssignEnaRewards() public {
        // takes a lot of time
        vm.skip(true);

        string memory json = vm.readFile("./script/data/enarewardsfinal.json");
        string[] memory keys = vm.parseJsonKeys(json, "$");
        address[] memory users = new address[](keys.length);
        uint256[] memory amounts = new uint256[](keys.length);
        for (uint256 index = 0; index < keys.length; index++) {
            uint256 amount = json.readUint(string.concat(".", keys[index]));
            address user = vm.parseAddress(keys[index]);
            users[index] = user;
            amounts[index] = amount;
        }

        vm.prank(_owner);
        _bridgerL2.assignENARewards(users, amounts);

        for (uint256 index = 0; index < keys.length; index++) {
            address user = users[index];
            uint256 amount = amounts[index];
            assertEq(_bridgerL2.deposits(user, ENA), amount, "Balance is wrong");
        }
    }
}

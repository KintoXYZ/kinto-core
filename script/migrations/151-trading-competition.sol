// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {BridgedToken} from "@kinto-core/tokens/bridged/BridgedToken.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {console2} from "forge-std/console2.sol";

contract TransferDclmScript is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;

    function run() public override {
        super.run();

        uint256 kadai_amount_1 = 50e18;
        uint256 kadai_amount_2 = 20e18;
        uint256 kadai_amount_3 = 10e18;

        uint256 kadai_amount_4 = 50e18;
        uint256 kadai_amount_5 = 20e18;
        uint256 kadai_amount_6 = 10e18;

        uint256 kadai_amount_7 = 50e18;

        address kadai_winner_1 = 0xa13D24d265EFbd84c993e525A210458CE15081b9;
        address kadai_winner_2 = 0x04bF0Fe175E23e3E4474712040f8EEBbf0484100;
        address kadai_winner_3 = 0x956642E471D5DA741b34aBB14d1B74b46583cD80;

        address kadai_winner_4 = 0x2025b0E5A1666c690E35f4638Fcfc319f03c8075;
        address kadai_winner_5 = 0xa13D24d265EFbd84c993e525A210458CE15081b9;
        address kadai_winner_6 = 0xCa42442258b9E9994Ec9EDe50b70bf1b3bAA491E;

        address kadai_winner_7 = 0x71F51C64110709880260610EA8C411A28c067739;

        address kintoToken = _getChainDeployment("KINTO");
        uint256 kadai_balanceBefore_1 = ERC20(kintoToken).balanceOf(kadai_winner_1);
        uint256 kadai_balanceBefore_2 = ERC20(kintoToken).balanceOf(kadai_winner_2);
        uint256 kadai_balanceBefore_3 = ERC20(kintoToken).balanceOf(kadai_winner_3);
        uint256 kadai_balanceBefore_4 = ERC20(kintoToken).balanceOf(kadai_winner_4);
        uint256 kadai_balanceBefore_5 = ERC20(kintoToken).balanceOf(kadai_winner_5);
        uint256 kadai_balanceBefore_6 = ERC20(kintoToken).balanceOf(kadai_winner_6);
        uint256 kadai_balanceBefore_7 = ERC20(kintoToken).balanceOf(kadai_winner_7);

        // Burn tokens from RD
        _handleOps(
            abi.encodeWithSelector(
                BridgedToken.burn.selector,
                _getChainDeployment("RewardsDistributor"),
                kadai_amount_1 + kadai_amount_2 + kadai_amount_3 + kadai_amount_4 + kadai_amount_5 + kadai_amount_6
                    + kadai_amount_7
            ),
            kintoToken
        );

        // Mint tokens to winner address
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, kadai_winner_1, kadai_amount_1), kintoToken);
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, kadai_winner_2, kadai_amount_2), kintoToken);
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, kadai_winner_3, kadai_amount_3), kintoToken);
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, kadai_winner_4, kadai_amount_4), kintoToken);
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, kadai_winner_5, kadai_amount_5), kintoToken);
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, kadai_winner_6, kadai_amount_6), kintoToken);
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, kadai_winner_7, kadai_amount_7), kintoToken);

        // Check that tokens received
        assertEq(ERC20(kintoToken).balanceOf(kadai_winner_1) - kadai_balanceBefore_1, kadai_amount_1);
        assertEq(ERC20(kintoToken).balanceOf(kadai_winner_2) - kadai_balanceBefore_2, kadai_amount_2);
        assertEq(ERC20(kintoToken).balanceOf(kadai_winner_3) - kadai_balanceBefore_3, kadai_amount_3);
        assertEq(ERC20(kintoToken).balanceOf(kadai_winner_4) - kadai_balanceBefore_4, kadai_amount_4);
        assertEq(ERC20(kintoToken).balanceOf(kadai_winner_5) - kadai_balanceBefore_5, kadai_amount_5);
        assertEq(ERC20(kintoToken).balanceOf(kadai_winner_6) - kadai_balanceBefore_6, kadai_amount_6);
        assertEq(ERC20(kintoToken).balanceOf(kadai_winner_7) - kadai_balanceBefore_7, kadai_amount_7);
    }
}

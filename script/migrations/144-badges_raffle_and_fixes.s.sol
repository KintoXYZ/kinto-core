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

        uint256 amount_1 = 50e18; // 50 KINTO
        uint256 amount_2 = 25e18; // 25 KINTO
        uint256 amount_3 = 105e16; // 1.05 KINTO
        uint256 amount_4 = 1e18; // 1 KINTO
        uint256 total_amount = amount_1 + amount_2 + amount_3 + amount_4;


        address winner_1 = 0x90038C150d7528F88AD2B13780886f72e6Cb033e;
        address winner_2 = 0xb14fBf93044fa716C9CF4bC8F112D1441aF2edad;
        address winner_3 = 0x97deBef83901141e56D5C541c0f282A66b144e11;
        address winner_4 = 0x0D8C40Ab2F2a67DF76892Ec15A368dE297f5A6d7;

        address kintoToken = _getChainDeployment("KINTO");
        uint256 balanceBefore_1 = ERC20(kintoToken).balanceOf(winner_1);
        uint256 balanceBefore_2 = ERC20(kintoToken).balanceOf(winner_2);
        uint256 balanceBefore_3 = ERC20(kintoToken).balanceOf(winner_3);
        uint256 balanceBefore_4 = ERC20(kintoToken).balanceOf(winner_4);

        // Burn tokens from RD
        _handleOps(
            abi.encodeWithSelector(
                BridgedToken.burn.selector,
                _getChainDeployment("RewardsDistributor"),
                total_amount
            ),
            kintoToken
        );

        // Mint tokens to winner address
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, winner_1, amount_1), kintoToken);
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, winner_2, amount_2), kintoToken);
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, winner_3, amount_3), kintoToken);
        _handleOps(abi.encodeWithSelector(BridgedToken.mint.selector, winner_4, amount_4), kintoToken);

        // Check that tokens received
        assertEq(ERC20(kintoToken).balanceOf(winner_1) - balanceBefore_1, amount_1);
        assertEq(ERC20(kintoToken).balanceOf(winner_2) - balanceBefore_2, amount_2);
        assertEq(ERC20(kintoToken).balanceOf(winner_3) - balanceBefore_3, amount_3);
        assertEq(ERC20(kintoToken).balanceOf(winner_4) - balanceBefore_4, amount_4);
    }
}

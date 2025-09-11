// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {BridgedToken} from "@kinto-core/tokens/bridged/BridgedToken.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FixVaultBalance is MigrationHelper {
    using Strings for string;

    function run() public override {
        super.run();

        BridgedKinto kintoToken = BridgedKinto(_getChainDeployment("KINTO"));
        address vaultAd = 0x3De040ef2Fbf9158BADF559C5606d7706ca72309;
        address devWallet = 0xf9e2E3F36C45F31ef4579c481C040772f086577b;

        uint256 vaultBalance = kintoToken.balanceOf(vaultAd);
        uint256 devBalance = kintoToken.balanceOf(devWallet);
        uint256 burnedAdmin = 1352661940777106379283442;
        uint256 arbBridged = 228074132415388490747789; // todo: grab

        uint256 diff = 228074132415388490747789 - vaultBalance;

        _handleOps(
            abi.encodeWithSelector(BridgedToken.mint.selector, vaultAd, arbBridged - vaultBalance),
            payable(_getChainDeployment("KINTO"))
        );

        _handleOps(
            abi.encodeWithSelector(BridgedToken.burn.selector, devWallet, diff), payable(_getChainDeployment("KINTO"))
        );

        require(kintoToken.balanceOf(vaultAd) == arbBridged, "Chains do not match");
        require(kintoToken.totalSupply() == 10_000_000e18, "Total supply incorrect");
    }
}

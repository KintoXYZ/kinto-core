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

contract Script is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;

    function run() public override {
        super.run();

        // ETH
        deployBridgedToken("aETH", "Aave WETH", 18, "AE7000");
        // WBTC
        deployBridgedToken("aWBTC", "Aave WBTC ", 8, "A0B7C0");
        // weETH
        deployBridgedToken("aweETH", "Aave weETH", 18, "A0EE70");
        // USDC
        deployBridgedToken("aUSDC", "Aave weETH", 6, "A06DC0");
        // USDT
        deployBridgedToken("aUSDT", "Aave USDT", 6, "A06D70");
        // ARB
        deployBridgedToken("aARB", "Aave ARB", 18, "AA9B00");
        // DAI
        deployBridgedToken("aDAI", "Aave DAI", 18, "ADA100");
        // LINK
        deployBridgedToken("aLINK", "Aave LINK", 18, "A11000");
        // GHO
        deployBridgedToken("aGHO", "Aave Gho", 18, "A60000");
        // rETH
        deployBridgedToken("arETH", "Aave rETH", 18, "A9E700");
        // cbETH
        deployBridgedToken("acbETH", "Aave cbETH", 18, "ACBE70");
        // cbBTC
        deployBridgedToken("acbBTC", "Aave cbBTC", 8, "ACBB7C");
    }
}

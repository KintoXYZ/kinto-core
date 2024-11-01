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

        // WBTC
        deployBridgedToken("WBTC", "WBTC ", 8, "0B7C00");
        // USDT
        deployBridgedToken("USDT", "USDT", 6, "06D700");
        // ARB
        deployBridgedToken("ARB", "ARB", 18, "A9B000");
        // DAI
        deployBridgedToken("DAI", "DAI", 18, "DA1000");
        // LINK
        deployBridgedToken("LINK", "LINK", 18, "110000");
        // GHO
        deployBridgedToken("GHO", "Gho", 18, "600000");
        // rETH
        deployBridgedToken("rETH", "rETH", 18, "9E7000");
        // cbETH
        deployBridgedToken("cbETH", "cbETH", 18, "CBE700");
        // cbBTC
        deployBridgedToken("cbBTC", "Coinbase Wrapped BTC", 8, "CBB7C0");
        // AAVE
        deployBridgedToken("AAVE", "Aave Token", 18, "AA0E00");
    }
}

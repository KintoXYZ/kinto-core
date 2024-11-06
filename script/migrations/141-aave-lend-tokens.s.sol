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
        deployBridgedToken("aEthWETH", "Aave Ethereum WETH", 18, "AEE700");
        deployBridgedToken("aArbWETH", "Aave Arbitrum WETH", 18, "AAE700");
        deployBridgedToken("aBasWETH", "Aave Base WETH", 18, "ABE700");
        // WBTC
        deployBridgedToken("aEthWBTC", "Aave Ethereum WBTC ", 8, "AE0B7C");
        deployBridgedToken("aArbWBTC", "Aave Arbitrum WBTC ", 8, "AA0B7C");
        deployBridgedToken("aBasWBTC", "Aave Base WBTC ", 8, "AB0B7C");
        // weETH
        deployBridgedToken("aEthweETH", "Aave Ethereum weETH", 18, "AE0EE7");
        deployBridgedToken("aArbweETH", "Aave Arbitrum weETH", 18, "AA0EE7");
        deployBridgedToken("aBasweETH", "Aave Base weETH", 18, "AB0EE7");
        // USDC
        deployBridgedToken("aEthUSDC", "Aave Ethereum USDC", 6, "AE06DC");
        deployBridgedToken("aArbUSDC", "Aave Arbitrum USDC", 6, "AA06DC");
        deployBridgedToken("aBasUSDC", "Aave Base USDC", 6, "AB06DC");
        // USDT
        deployBridgedToken("aEthUSDT", "Aave Ethereum USDT", 6, "AE06D7");
        deployBridgedToken("aArbUSDT", "Aave Arbitrum USDT", 6, "AA06D7");
        deployBridgedToken("aBasUSDT", "Aave Base USDT", 6, "AB06D7");
        // ARB
        deployBridgedToken("aEthARB", "Aave Ethereum ARB", 18, "AEA9B0");
        deployBridgedToken("aArbARB", "Aave Arbitrum ARB", 18, "AAA9B0");
        deployBridgedToken("aBasARB", "Aave Base ARB", 18, "ABA9B0");
        // DAI
        deployBridgedToken("aEthDAI", "Aave Ethereum DAI", 18, "AEDA10");
        deployBridgedToken("aArbDAI", "Aave Arbitrum DAI", 18, "AADA10");
        deployBridgedToken("aBasDAI", "Aave Base DAI", 18, "ABDA10");
        // LINK
        deployBridgedToken("aEthLINK", "Aave Ethereum LINK", 18, "AE1100");
        deployBridgedToken("aArbLINK", "Aave Arbitrum LINK", 18, "AA1100");
        deployBridgedToken("aBasLINK", "Aave Base LINK", 18, "AB1100");
        // GHO
        deployBridgedToken("aEthGHO", "Aave Ethereum Gho", 18, "AE6000");
        deployBridgedToken("aArbGHO", "Aave Arbitrum Gho", 18, "AA6000");
        deployBridgedToken("aBasGHO", "Aave Base Gho", 18, "AB6000");
        // rETH
        deployBridgedToken("aEthrETH", "Aave Ethereum rETH", 18, "AE9E70");
        deployBridgedToken("aArbrETH", "Aave Arbitrum rETH", 18, "AA9E70");
        deployBridgedToken("aBasrETH", "Aave Base rETH", 18, "AB9E70");
        // cbETH
        deployBridgedToken("aEthcbETH", "Aave Ethereum cbETH", 18, "AECBE7");
        deployBridgedToken("aArbcbETH", "Aave Arbitrum cbETH", 18, "AACBE7");
        deployBridgedToken("aBascbETH", "Aave Base cbETH", 18, "ABCBE7");
        // cbBTC
        deployBridgedToken("aEthcbBTC", "Aave Ethereum cbBTC", 8, "AECBB7");
        deployBridgedToken("aArbcbBTC", "Aave Arbitrum cbBTC", 8, "AACBB7");
        deployBridgedToken("aBascbBTC", "Aave Base cbBTC", 8, "ABCBB7");
        // Aave
        deployBridgedToken("aEthAAVE", "Aave Ethereum AAVE", 18, "AEAA0E");
        deployBridgedToken("aArbAAVE", "Aave Arbitrum AAVE", 18, "AAAA0E");
        deployBridgedToken("aBasAAVE", "Aave Base AAVE", 18, "ABAA0E");
        // wstETH
        deployBridgedToken("aEthwstETH", "Aave Ethereum wstETH", 18, "AE067E");
        deployBridgedToken("aArbwstETH", "Aave Arbitrum wstETH", 18, "AA067E");
        deployBridgedToken("aBaswstETH", "Aave Base wstETH", 18, "AB067E");
    }
}

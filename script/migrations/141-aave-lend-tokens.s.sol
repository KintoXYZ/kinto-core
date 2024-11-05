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
        deployBridgedToken("aEthWETH", "Aave Ethereum WETH", 18, "AE7000");
        deployBridgedToken("aArbWETH", "Aave Arbitrum WETH", 18, "AE7000");
        deployBridgedToken("aBasWETH", "Aave Base WETH", 18, "AE7000");
        // WBTC
        deployBridgedToken("aEthWBTC", "Aave Ethereum WBTC ", 8, "A0B7C0");
        deployBridgedToken("aArbWBTC", "Aave Arbitrum WBTC ", 8, "A0B7C0");
        deployBridgedToken("aBasWBTC", "Aave Base WBTC ", 8, "A0B7C0");
        // weETH
        deployBridgedToken("aweEthETH", "Aave Ethereum weETH", 18, "A0EE70");
        deployBridgedToken("aweArbETH", "Aave Arbitrum weETH", 18, "A0EE70");
        deployBridgedToken("aweBasETH", "Aave Base weETH", 18, "A0EE70");
        // USDC
        deployBridgedToken("aEthUSDC", "Aave Ethereum weETH", 6, "A06DC0");
        deployBridgedToken("aArbUSDC", "Aave Arbitrum weETH", 6, "A06DC0");
        deployBridgedToken("aBasUSDC", "Aave Base weETH", 6, "A06DC0");
        // USDT
        deployBridgedToken("aEthUSDT", "Aave Ethereum USDT", 6, "A06D70");
        deployBridgedToken("aArbUSDT", "Aave Arbitrum USDT", 6, "A06D70");
        deployBridgedToken("aBasUSDT", "Aave Base USDT", 6, "A06D70");
        // ARB
        deployBridgedToken("aEthARB", "Aave Ethereum ARB", 18, "AA9B00");
        deployBridgedToken("aArbARB", "Aave Arbitrum ARB", 18, "AA9B00");
        deployBridgedToken("aBasARB", "Aave Base ARB", 18, "AA9B00");
        // DAI
        deployBridgedToken("aEthDAI", "Aave Ethereum DAI", 18, "ADA100");
        deployBridgedToken("aArbDAI", "Aave Arbitrum DAI", 18, "ADA100");
        deployBridgedToken("aBasDAI", "Aave Base DAI", 18, "ADA100");
        // LINK
        deployBridgedToken("aEthLINK", "Aave Ethereum LINK", 18, "A11000");
        deployBridgedToken("aArbLINK", "Aave Arbitrum LINK", 18, "A11000");
        deployBridgedToken("aBasLINK", "Aave Base LINK", 18, "A11000");
        // GHO
        deployBridgedToken("aEthGHO", "Aave Ethereum Gho", 18, "A60000");
        deployBridgedToken("aArbGHO", "Aave Arbitrum Gho", 18, "A60000");
        deployBridgedToken("aBasGHO", "Aave Base Gho", 18, "A60000");
        // rETH
        deployBridgedToken("arEthETH", "Aave Ethereum rETH", 18, "A9E700");
        deployBridgedToken("arArbETH", "Aave Arbitrum rETH", 18, "A9E700");
        deployBridgedToken("arBasETH", "Aave Base rETH", 18, "A9E700");
        // cbETH
        deployBridgedToken("acbEthETH", "Aave Ethereum cbETH", 18, "ACBE70");
        deployBridgedToken("acbArbETH", "Aave Arbitrum cbETH", 18, "ACBE70");
        deployBridgedToken("acbBasETH", "Aave Base cbETH", 18, "ACBE70");
        // cbBTC
        deployBridgedToken("acbEthBTC", "Aave Ethereum cbBTC", 8, "ACBB7C");
        deployBridgedToken("acbArbBTC", "Aave Arbitrum cbBTC", 8, "ACBB7C");
        deployBridgedToken("acbBasBTC", "Aave Base cbBTC", 8, "ACBB7C");
        // Aave
        deployBridgedToken("aEthAAVE", "Aave Ethereum AAVE", 18, "AAA0E0");
        deployBridgedToken("aArbAAVE", "Aave Arbitrum AAVE", 18, "AAA0E0");
        deployBridgedToken("aBasAAVE", "Aave Base AAVE", 18, "AAA0E0");
        // wstETH
        deployBridgedToken("awstEthETH", "Aave Ethereum wstETH", 18, "A067E7");
        deployBridgedToken("awstArbETH", "Aave Arbitrum wstETH", 18, "A067E7");
        deployBridgedToken("awstBasETH", "Aave Base wstETH", 18, "A067E7");
    }
}

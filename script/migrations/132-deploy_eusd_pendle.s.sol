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

contract DeployKintoScript is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;

    function run() public override {
        super.run();

        deployBridgedToken("eUSD", "ether.fi USD", 18, "e05D00");
        deployBridgedToken("rsENA", "rsENA", 18, "25E0A0");
        deployBridgedToken("rsUSDe", "rsUSDe", 18, "2505DE");
    }
}

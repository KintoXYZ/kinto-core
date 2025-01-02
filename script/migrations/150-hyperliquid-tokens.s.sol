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

        deployBridgedToken("USUAL", "USUAL", 18, "050A10");
        deployBridgedToken("LDO", "Lido DAO Token", 18, "1D0000");
        deployBridgedToken("VIRTUAL", "Virtual Protocol", 18, "01900A");
        deployBridgedToken("ONDO", "Ondo", 18, "00D000");
        deployBridgedToken("PENDLE", "Pendle", 18, "9E0D1E");
        deployBridgedToken("CRV", "Curve DAO Token", 18, "C90000");
    }
}

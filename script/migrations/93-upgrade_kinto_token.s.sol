// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract UpgradeKintoTokenDeployScript is MigrationHelper {
    using Strings for string;

    function run() public override {
        super.run();

        address impl = _deployImplementationAndUpgrade("KINTO", "V3", abi.encodePacked(type(BridgedKinto).creationCode));

        BridgedKinto bridgedToken = BridgedKinto(_getChainDeployment("KINTO"));

        require(bridgedToken.decimals() == 18, "Decimals mismatch");
        require(bridgedToken.symbol().equal("K"), "");
        require(bridgedToken.name().equal("Kinto Token"), "");

        saveContractAddress("KV3-impl", impl);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract UpgradeKintoTokenDeployScript is MigrationHelper {
    using Strings for string;

    function run() public override {
        super.run();

        address impl = _deployImplementationAndUpgrade("KINTO", "V8", abi.encodePacked(type(BridgedKinto).creationCode));

        BridgedKinto kintoToken = BridgedKinto(_getChainDeployment("KINTO"));

        require(kintoToken.decimals() == 18, "Decimals mismatch");
        require(kintoToken.symbol().equal("K"), "");
        require(kintoToken.name().equal("Kinto Token"), "");

        saveContractAddress("KV8-impl", impl);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {KintoToken} from "@kinto-core/tokens/KintoToken.sol";
import {MiningAdaptor} from "@kinto-core/liquidity-mining/MiningAdaptor.sol";

import {Create2Helper} from "@kinto-core-test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {DeployerHelper} from "@kinto-core-script/utils/DeployerHelper.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

contract DeployMiningAdaptorScript is Create2Helper, ArtifactsReader, DeployerHelper, Test {
    function run() public {
        if (block.chainid != 1) {
            console.log("This script is meant to be run on the mainnet");
            return;
        }
        vm.broadcast();
        MiningAdaptor adaptor = new MiningAdaptor();

        // Checks
        assertEq(adaptor.KINTO(), 0x2367C8395a283f0285c6E312D5aA15826f1fEA25);
        assertEq(adaptor.KINTO_MINING_CONTRACT(), 0xD157904639E89df05e89e0DabeEC99aE3d74F9AA);

        saveContractAddress("MiningAdaptor", address(adaptor));
    }
}

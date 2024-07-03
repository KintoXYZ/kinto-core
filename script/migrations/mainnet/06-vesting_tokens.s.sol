// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {KintoToken} from "@kinto-core/tokens/KintoToken.sol";
import {VestingContract} from "@kinto-core/tokens/VestingContract.sol";


import {Create2Helper} from "@kinto-core-test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {DeployerHelper} from "@kinto-core/libraries/DeployerHelper.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

contract DeployMiningAdaptorScript is Create2Helper, ArtifactsReader, DeployerHelper, Test {
    function run() public {
        if (block.chainid != 1) {
            console.log("This script is meant to be run on the mainnet");
            return;
        }
        vm.startBroadcast();
    }
}
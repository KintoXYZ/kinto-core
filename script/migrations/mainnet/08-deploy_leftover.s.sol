pragma solidity ^0.8.24;

import {KintoLeftOver} from "@kinto-core/vaults/KintoLeftOver.sol";

import {Create2Helper} from "@kinto-core-test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {DeployerHelper} from "@kinto-core-script/utils/DeployerHelper.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

contract DeployKintoLeftOverScript is Create2Helper, ArtifactsReader, DeployerHelper, Test {
    function run() public {
        if (block.chainid != 1) {
            console.log("This script is meant to be run on the mainnet");
            return;
        }
        vm.broadcast();
        KintoLeftOver kovr = new KintoLeftOver({});

        // Checks
        assertEq(address(kovr.USDC()), 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        assertEq(kovr.OWNER(), 0x2E7111Ef34D39b36EC84C656b947CA746e495Ff6);

        saveContractAddress("KintoLeftOver", address(kovr));
    }
}

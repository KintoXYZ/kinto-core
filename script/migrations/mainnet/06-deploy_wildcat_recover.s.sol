pragma solidity ^0.8.24;

import {WildcatRepayment} from "@kinto-core/vaults/WildcatRepayment.sol";

import {Create2Helper} from "@kinto-core-test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {DeployerHelper} from "@kinto-core-script/utils/DeployerHelper.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

contract DeployWildcatRecoverScript is Create2Helper, ArtifactsReader, DeployerHelper, Test {
    function run() public {
        if (block.chainid != 1) {
            console.log("This script is meant to be run on the mainnet");
            return;
        }
        vm.broadcast();
        WildcatRepayment wildcatRepayment = new WildcatRepayment();

        // Checks
        assertEq(address(wildcatRepayment.USDC()), 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        assertEq(wildcatRepayment.OWNER(), 0x2E7111Ef34D39b36EC84C656b947CA746e495Ff6);

        saveContractAddress("WildcatRepayment", address(wildcatRepayment));
    }
}

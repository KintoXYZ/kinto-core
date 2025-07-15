// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SuperToken} from "@kinto-core/tokens/bridged/SuperToken.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

import {Constants} from "@kinto-core-script/migrations/mainnet/const.sol";

contract DeployScript is Constants, Test, MigrationHelper {
    address internal token;

    function setUp() public {}

    function run() public override {
        super.run();

        token = _getChainDeployment("K", block.chainid);
        if (token != address(0)) {
            console.log("Deployed",  token);
            return;
        }

        // Deploy implementation
        vm.broadcast(deployerPrivateKey);
        token = address(new SuperToken(18, "Kinto", "K", deployer));

        // Checks
        assertEq(SuperToken(token).decimals(), 18, "Invalid decimals");
        assertEq(SuperToken(token).name(), 'Kinto', "Invalid name");
        assertEq(SuperToken(token).symbol(), 'K', "Invalid symbol");

        saveContractAddress("K", token);
    }
}

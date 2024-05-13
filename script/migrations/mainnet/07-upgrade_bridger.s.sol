// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../../src/bridger/Bridger.sol";

import "../../../test/helpers/Create2Helper.sol";
import "../../../test/helpers/ArtifactsReader.sol";
import "../../../test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

contract KintoMainnetMigration7DeployScript is Create2Helper, ArtifactsReader, Test {
    Bridger _bridger;

    function setUp() public {}

    function run() public {
        if (block.chainid != 1) {
            console.log("This script is meant to be run on the mainnet");
            return;
        }

        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));

        // If not using ledger, replace
        console.log("Executing with address", msg.sender);

        address bridgerAddress = _getChainDeployment("Bridger", 1);
        if (bridgerAddress == address(0)) {
            console.log("Not deployed bridger", bridgerAddress);
            return;
        }
        address bridgerAddressL2 = _getChainDeployment("BridgerL2", 7887);

        // Deploy BridgerV4 implementation
        vm.broadcast();
        BridgerV4 _newImplementation = new BridgerV4(bridgerAddressL2);

        // NOTE: upgrade not broadcast since it needs to happen via SAFE
        // Bridger(payable(bridgerAddress)).upgradeTo(address(_newImplementation));

        // write addresses to file
        console.log("Add these addresses to the artifacts mainnet file");
        console.log(string.concat('"BridgerV4-impl": "', vm.toString(address(_newImplementation)), '"'));
    }
}

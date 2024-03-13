// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../../src/bridger/Bridger.sol";

import "../../../test/helpers/Create2Helper.sol";
import "../../../test/helpers/ArtifactsReader.sol";
import "../../../test/helpers/UUPSProxy.sol";


import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";


contract KintoMainnetMigration3DeployScript is Create2Helper, ArtifactsReader, Test {

    function setUp() public {}

    function run() public {
        if (block.chainid != 1) {
            console.log("This script is meant to be run on the mainnet");
            return;
        }
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // If not using ledger, replace
        console.log("Executing with address", msg.sender);
        vm.startBroadcast();
        address bridgerAddress = _getChainDeployment("Bridger", 1);
        if (bridgerAddress == address(0)) {
            console.log("Not deployed bridger", bridgerAddress);
            return;
        }

        address bridgerAddressL2 = _getChainDeployment("BridgerL2", 7887);
        if (bridgerAddressL2 == address(0)) {
            console.log("Not deployed bridger L2", bridgerAddressL2);
            return;
        }

        // Deploy Engen Credits implementation
        Bridger bridger = Bridger(payable(bridgerAddress));
        bridger.setSwapsEnabled(true);
        vm.stopBroadcast();
  
        // Checks
        assertEq(bridger.swapsEnabled(), true);
    }
}

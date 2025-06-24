// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MorphoRoycoAdaptor} from "@kinto-core/royco/MorphoRoycoAdaptor.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

import {Constants} from "@kinto-core-script/migrations/arbitrum/const.sol";

contract DeployMorphoRoycoAdaptorScript is Constants, Test, MigrationHelper {
    function setUp() public {}

    function run() public override {
        super.run();
        console.log("Executing with address", msg.sender);

        if (block.chainid != ARBITRUM_CHAINID) {
            console2.log("This script is meant to be run on the chain: %s", ARBITRUM_CHAINID);
            return;
        }
        address morphoRoycoAdaptorAddress = _getChainDeployment("MorphoRoycoAdaptor", ARBITRUM_CHAINID);
        if (morphoRoycoAdaptorAddress != address(0)) {
            console2.log("Already deployed MorphoRoycoAdaptor", morphoRoycoAdaptorAddress);
            return;
        }

        vm.broadcast();
        MorphoRoycoAdaptor morphoAdaptor = new MorphoRoycoAdaptor();
        console2.log("MorphoRoycoAdaptor deployed at ", address(morphoAdaptor));

        // Checks
        assertEq(morphoAdaptor.ORACLE(), 0x2964aB84637d4c3CAF0Fd968be1c97D9990de925, "Invalid ORACLE");
        saveContractAddress("MorphoRoycoAdaptor", address(morphoAdaptor));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../../src/bridger/Bridger.sol";

import "../../../test/helpers/Create2Helper.sol";
import "../../../test/helpers/ArtifactsReader.sol";
import "../../../test/helpers/UUPSProxy.sol";

import {Constants} from "@kinto-core-script/migrations/mainnet/const.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

contract DeployBridgerScript is Create2Helper, ArtifactsReader, Test, Constants {
    Bridger _bridger;

    // Exchange Proxy address is the same on all chains.

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
        if (bridgerAddress != address(0)) {
            console.log("Already deployed bridger", bridgerAddress);
            return;
        }

        Bridger _implementation = new Bridger(EXCHANGE_PROXY, address(0), WETH, DAI, USDe, sUSDe, wstETH);
        console.log("Bridger implementation deployed at", address(_implementation));
        // deploy proxy contract and point it to implementation
        UUPSProxy _proxy = new UUPSProxy{salt: 0}(address(_implementation), "");
        // wrap in ABI to support easier calls
        _bridger = Bridger(payable(address(_proxy)));
        console.log("Bridger proxy deployed at ", address(_bridger));
        // Initialize proxy
        _bridger.initialize(0x6E09F8A68fB5278e0C33D239dC12B2Cec33F4aC7);
        vm.stopBroadcast();

        // Checks
        assertEq(_bridger.senderAccount(), 0x6E09F8A68fB5278e0C33D239dC12B2Cec33F4aC7);
        assertEq(_bridger.owner(), vm.envAddress("LEDGER_ADMIN"));

        // Writes the addresses to a file
        console.log("Add these addresses to the artifacts mainnet file");
        console.log(string.concat('"Bridger": "', vm.toString(address(_bridger)), '"'));
        console.log(string.concat('"BridgerV1-impl": "', vm.toString(address(_implementation)), '"'));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../../src/bridger/Bridger.sol";

import "../../../test/helpers/Create2Helper.sol";
import "../../../test/helpers/ArtifactsReader.sol";
import "../../../test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

import {Constants} from "@kinto-core-script/migrations/mainnet/const.sol";

contract UpgradeBridgerScript is Create2Helper, ArtifactsReader, Test, Constants {
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
        vm.startBroadcast();

        address bridgerAddress = _getChainDeployment("Bridger", 1);
        if (bridgerAddress == address(0)) {
            console.log("Not deployed bridger", bridgerAddress);
            return;
        }

        Bridger newImpl = new Bridger(L2_VAULT, BRIDGE, EXCHANGE_PROXY, WETH, DAI, USDE, SUSDE, WSTETH);

        vm.stopBroadcast();

        _bridger = Bridger(payable(bridgerAddress));
        // NOTE: upgrade not broadcast since it needs to happen via SAFE
        _bridger.upgradeTo(address(newImpl));
        // prank
        Bridger(payable(bridgerAddress)).upgradeTo(address(newImpl));

        // Checks
        assertEq(_bridger.senderAccount(), 0x6E09F8A68fB5278e0C33D239dC12B2Cec33F4aC7);
        assertEq(_bridger.l2Vault(), 0x26181Dfc530d96523350e895180b09BAf3d816a0);
        assertEq(_bridger.owner(), vm.envAddress("LEDGER_ADMIN"));

        // Writes the addresses to a file
        console.log("Add these addresses to the artifacts mainnet file");
        console.log(string.concat('"Bridger-impl": "', vm.toString(address(newImpl)), '"'));
    }
}

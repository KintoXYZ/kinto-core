// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/Faucet.sol";
import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoMigration5DeployScript is Create2Helper, ArtifactsReader {
    Faucet _faucet;

    function setUp() public {}

    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // If not using ledger, replace
        // uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        // vm.startBroadcast(deployerPrivateKey);
        console.log("Executing with address", msg.sender);
        vm.startBroadcast();
        address faucetAddr = _getChainDeployment("Faucet");
        if (faucetAddr != address(0)) {
            console.log("Faucet already deployed", faucetAddr);
            return;
        }
        _faucet = new Faucet(address(0));
        vm.stopBroadcast();
        // Writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"Faucet": "', vm.toString(address(_faucet)), '"'));
    }
}

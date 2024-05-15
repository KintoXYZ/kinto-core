// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/sample/Counter.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoMigration6DeployScript is Create2Helper, ArtifactsReader {
    Counter _counter;

    function setUp() public {}

    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // If not using ledger, replace
        // uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        // vm.startBroadcast(deployerPrivateKey);
        console.log("Executing with address", msg.sender);
        vm.startBroadcast();
        address walletFactoryAddr = _getChainDeployment("KintoWalletFactory");
        if (walletFactoryAddr == address(0)) {
            console.log("Need to execute main deploy script first", walletFactoryAddr);
            return;
        }
        _counter = new Counter();
        for (uint256 i = 0; i < 14; i++) {
            _counter.increment();
        }
        vm.stopBroadcast();
        // Writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"Counter": "', vm.toString(address(_counter)), '"'));
    }
}

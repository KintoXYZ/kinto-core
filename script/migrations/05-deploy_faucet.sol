// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../../src/Faucet.sol";
import {Create2Helper} from "../../test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "../../test/helpers/UUPSProxy.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/console.sol";

contract KintoMigration5DeployScript is Create2Helper, ArtifactsReader {
    using ECDSAUpgradeable for bytes32;

    Faucet _faucet;

    function setUp() public {}

    // solhint-disable code-complexity
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
        _faucet = new Faucet();
        vm.stopBroadcast();
        // Writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"Faucet": "', vm.toString(address(_faucet)), '"'));
    }
}

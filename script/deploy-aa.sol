// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "@aa/core/EntryPoint.sol";
import "forge-std/console.sol";

contract KintoAADeploy is Script {

    // EntryPoint _entryPoint;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // _entryPoint = new EntryPoint{salt: bytes32(uint256(1337))}();
        vm.stopBroadcast();
    }
}

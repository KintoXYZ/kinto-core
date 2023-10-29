// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/console.sol';
import 'forge-std/Script.sol';

abstract contract ArtifactsReader is Script {

    function _getAddressesFile() internal view returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/test/artifacts/", vm.toString(block.chainid), "/addresses.json");
    }

    function _getChainDeployment(string memory contractName) internal returns (address) {
        try vm.readFile(_getAddressesFile()) returns (string memory json){
            try vm.parseJsonAddress(json, string.concat('.', contractName)) returns (address addr) {
                return addr;
            } catch {
                return address(0);
            } 
        } catch {
            return address(0);
        }
    }

}
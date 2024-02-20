// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";

abstract contract ArtifactsReader is Script {
    function _getAddressesFile() internal view virtual returns (string memory) {
        return _getAddressesFile(block.chainid);
    }

    function _getAddressesFile(uint256 chainid) internal view virtual returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/test/artifacts/", vm.toString(chainid), "/addresses.json");
    }

    function _getChainDeployment(string memory contractName) internal virtual returns (address) {
        return _getChainDeployment(contractName, block.chainid);
    }

    function _getChainDeployment(string memory contractName, uint256 chainId) internal virtual returns (address) {
        try vm.readFile(_getAddressesFile(chainId)) returns (string memory json) {
            try vm.parseJsonAddress(json, string.concat(".", contractName)) returns (address addr) {
                return addr;
            } catch {
                return address(0);
            }
        } catch {
            return address(0);
        }
    }
}

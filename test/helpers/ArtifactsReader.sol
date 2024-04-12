// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";

abstract contract ArtifactsReader is Script {
    function _getAddressesDir(uint256 chainId) internal view virtual returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/test/artifacts/", vm.toString(chainId));
    }

    function _getAddressesDir() internal view virtual returns (string memory) {
        return _getAddressesDir(block.chainid);
    }

    function _getAddressesFile() internal view virtual returns (string memory) {
        return _getAddressesFile(block.chainid);
    }

    function _getAddressesFile(uint256 chainid) internal view virtual returns (string memory) {
        return string.concat(_getAddressesDir(chainid), "/addresses.json");
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

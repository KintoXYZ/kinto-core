// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";

import {Create2Helper} from "../../test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";

abstract contract DeployerHelper is Create2Helper, ArtifactsReader {
    using stdJson for string;

    function getWethByChainId(uint256 chainid) public view returns (address) {
        // local
        if (chainid == 31337) {
            return 0x4200000000000000000000000000000000000006;
        }
        // mainnet
        if (chainid == 1) {
            return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        }
        // base
        if (chainid == 8453) {
            return 0x4200000000000000000000000000000000000006;
        }
        // arbitrum one
        if (chainid == 42161) {
            return 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        }
        // optimism
        if (chainid == 10) {
            return 0x4200000000000000000000000000000000000006;
        }
        revert(string.concat("No WETH address for chainid:", vm.toString(block.chainid)));
    }

    function create2(bytes memory creationCodeWithArgs) internal returns (address addr) {
        return create2(creationCodeWithArgs, 0);
    }

    function create2(bytes memory creationCodeWithArgs, bytes32 salt) internal returns (address addr) {
        console2.log("keccak256(creationCodeWithArgs)");
        console2.logBytes32(keccak256(creationCodeWithArgs));
        addr = computeAddress(salt, creationCodeWithArgs);
        if (!isContract(addr)) {
            address deployed = deploy(salt, creationCodeWithArgs);
            require(deployed == addr, "Deployed and compute addresses do not match");
        }
    }

    function saveContractAddress(string memory contractName, address addr) internal {
        string memory path = _getAddressesFile();
        string memory dir = _getAddressesDir();
        if (!vm.isDir(dir)) vm.createDir(dir, true);
        if (!vm.isFile(path)) {
            vm.writeFile(path, "{}");
        }

        // Execute jq with direct JSON object
        string[] memory inputs = new string[](3);
        inputs[0] = "jq";
        inputs[1] = string.concat('. + {"', contractName, '": "', vm.toString(addr), '"}');
        inputs[2] = path;

        vm.writeFile(path, string(vm.ffi(inputs)));
    }
}

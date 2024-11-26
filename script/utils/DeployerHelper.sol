// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";

import {Create2Helper} from "../../test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";

abstract contract DeployerHelper is Create2Helper, ArtifactsReader {
    using stdJson for string;


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

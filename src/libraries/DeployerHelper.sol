// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";

import {Create2Helper} from "../../test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";

abstract contract DeployerHelper is Create2Helper, ArtifactsReader {
    using stdJson for string;

    function create2(string memory contractName, bytes memory creationCodeWithArgs) internal returns (address addr) {
        addr = computeAddress(creationCodeWithArgs);
        console2.log('Deploying:', contractName);
        console2.log("compute:", addr);
        if (!isContract(addr)) {
            address deployed = deploy(creationCodeWithArgs);
            require(deployed == addr, "Deployed and compute addresses do not match");

            string memory finalJson = vm.serializeAddress('key', contractName, addr);
            vm.writeJson(finalJson, _getAddressesFile());
        }
    }
}

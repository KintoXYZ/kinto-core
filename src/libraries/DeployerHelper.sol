// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import {Create2Helper} from "../../test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";

abstract contract DeployerHelper is Create2Helper, ArtifactsReader {
    using stdJson for string;

    function create2(string memory contractName, bytes memory creationCodeWithArgs) internal returns (address addr) {
        addr = computeAddress(0, creationCodeWithArgs);

        if (!isContract(addr)) {
            address deployed = deploy(0, 0, creationCodeWithArgs);
            revert(deployed != addr, "Deployed and compute address do not match");
        }

        string memory addressesJson = vm.readFile(_getAddressesFile());
        string memory finalJson = addressesJson.serialize(contractName, vm.toString(address(addr)));
        finalJson.write(_getAddressesFile());
    }
}

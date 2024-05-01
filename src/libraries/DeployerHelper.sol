// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";

import {Create2Helper} from "../../test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";

abstract contract DeployerHelper is Create2Helper, ArtifactsReader {
    using stdJson for string;

    function run() public {
        console2.log("Running on chain with id:", vm.toString(block.chainid));
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        console2.log("Deployer:", deployer);

        vm.startBroadcast(privateKey);

        deployContracts(deployer);

        vm.stopBroadcast();

        checkContracts(deployer);
    }

    function deployContracts(address deployer) internal virtual;

    function checkContracts(address deployer) internal virtual;

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

    function create2(string memory contractName, bytes memory creationCodeWithArgs) internal returns (address addr) {
        return create2(0, contractName, creationCodeWithArgs);
    }

    function create2(bytes32 salt, string memory contractName, bytes memory creationCodeWithArgs)
        internal
        returns (address addr)
    {
        addr = computeAddress(salt, creationCodeWithArgs);
        if (!isContract(addr)) {
            address deployed = deploy(salt, creationCodeWithArgs);
            require(deployed == addr, "Deployed and compute addresses do not match");

            saveContractAddress(contractName, addr);
        }
    }

    function saveContractAddress(string memory contractName, address addr) internal {
        string memory path = _getAddressesFile();
        if (!vm.isFile(path)) {
            vm.writeFile(path, "{}");
        }

        string memory json = vm.readFile(path);
        string[] memory keys = vm.parseJsonKeys(json, "$");
        for (uint256 index = 0; index < keys.length; index++) {
            vm.serializeString(contractName, keys[index], json.readString(string.concat(".", keys[index])));
        }
        vm.writeJson(vm.serializeAddress(contractName, contractName, addr), path);
    }
}

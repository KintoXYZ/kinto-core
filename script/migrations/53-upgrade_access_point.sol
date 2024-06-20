// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {AccessPoint} from "@kinto-core/access/AccessPoint.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

contract UpgradeAccessPointScript is Script, MigrationHelper {
    address payable internal constant ENTRY_POINT = payable(0x0000000071727De22E5E9d8BAf0edAc6f37da032);

    AccessRegistry registry;
    AccessPoint newImpl;

    function run() public override {
        super.run();

        registry = AccessRegistry(_getChainDeployment("AccessRegistry"));
        if (address(registry) == address(0)) {
            console2.log("Access Protocol has to be deployed");
            return;
        }

        newImpl = AccessPoint(
            payable(create2(abi.encodePacked(type(AccessPoint).creationCode, abi.encode(ENTRY_POINT, registry))))
        );
        registry.upgradeAll(newImpl);

        require(address(newImpl.entryPoint()) == ENTRY_POINT, "Wrong entry point address");
    }
}

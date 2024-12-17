// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";
import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";

contract KintoCoreAppScript is MigrationHelper {
    address[] newContracts;

    function run() public override {
        super.run();

        KintoAppRegistry registry = KintoAppRegistry(_getChainDeployment("KintoAppRegistry"));

        address[] memory systemContracts = registry.getSystemContracts();

        // Copy all elements after the first 5
        for (uint256 i = 0; i < systemContracts.length - 5; i++) {
            newContracts.push(systemContracts[i + 5]);
        }

        newContracts.push(0x0000000000000000000000000000000000000064);

        address accessManager = _getChainDeployment("AccessManager");

        _handleOps(
            abi.encodeWithSelector(
                AccessManager.execute.selector,
                address(registry),
                abi.encodeWithSelector(KintoAppRegistry.updateSystemContracts.selector, newContracts)
            ),
            accessManager
        );

        address[] memory updatedSystemContracts = registry.getSystemContracts();
        for (uint256 index = 0; index < systemContracts.length; index++) {
            assertEq(systemContracts[index], updatedSystemContracts[index]);
        }

        assertEq(0x0000000000000000000000000000000000000064, updatedSystemContracts[updatedSystemContracts.length - 1]);
    }
}

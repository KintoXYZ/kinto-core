// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";

contract AddProtoGovPropToCoreScript is MigrationHelper {
    function run() public override {
        super.run();

        address parentContract = address(0xD157904639E89df05e89e0DabeEC99aE3d74F9AA); // Core App

        // Add ProtoGovernance contract to the Core App
        address[] memory appContracts = new address[](1);
        appContracts[0] = _getChainDeployment("ProtoGovernance");

        // Use addAppContracts function
        _handleOps(
            abi.encodeWithSelector(KintoAppRegistry.addAppContracts.selector, parentContract, appContracts),
            address(_getChainDeployment("KintoAppRegistry"))
        );
    }
}

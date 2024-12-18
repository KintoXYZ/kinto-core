// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";

contract KintoMigration78DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        KintoAppRegistry kintoAppRegistry = KintoAppRegistry(payable(_getChainDeployment("KintoAppRegistry")));

        address parentContract = address(0x3e9727470C66B1e77034590926CDe0242B5A3dCc); // Socket-DL contract

        uint256[4] memory appLimits =
            [RATE_LIMIT_PERIOD, RATE_LIMIT_THRESHOLD, GAS_LIMIT_PERIOD, GAS_LIMIT_THRESHOLD * 2];

        IKintoAppRegistry.Metadata memory metadata = kintoAppRegistry.getAppMetadata(parentContract);

        _handleOps(
            abi.encodeWithSelector(
                KintoAppRegistry.updateMetadata.selector,
                "Socket",
                parentContract,
                metadata.appContracts,
                appLimits,
                metadata.devEOAs
            ),
            address(_getChainDeployment("KintoAppRegistry"))
        );
    }
}

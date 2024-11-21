// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";
import "@kinto-core-test/helpers/ArrayHelpers.sol";

contract KintoMigration97DeployScript is MigrationHelper {
    using ArrayHelpers for *;

    function run() public override {
        super.run();

        KintoAppRegistry kintoAppRegistry = KintoAppRegistry(payable(_getChainDeployment("KintoAppRegistry")));

        address socketApp = 0x3e9727470C66B1e77034590926CDe0242B5A3dCc; // Socket-DL contract

        _handleOps(
            abi.encodeWithSelector(
                KintoAppRegistry.addAppContracts.selector,
                socketApp,
                [
                    0xd0d4cDB49DDa0F9B4785B3823eEdaA84B84afAd9, // USDT Vault
                    0x04481a364aCfD0776a30a6731D9Ee5425b9300EA // WBTC Vault
                ].toMemoryArray()
            ),
            address(_getChainDeployment("KintoAppRegistry"))
        );

        assertEq(kintoAppRegistry.getApp(0xd0d4cDB49DDa0F9B4785B3823eEdaA84B84afAd9), socketApp);
        assertEq(kintoAppRegistry.getApp(0x04481a364aCfD0776a30a6731D9Ee5425b9300EA), socketApp);
    }
}

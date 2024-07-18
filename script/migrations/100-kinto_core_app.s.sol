// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoAppRegistry, KintoAppRegistryV9} from "@kinto-core/apps/KintoAppRegistry.sol";

contract KintoCoreAppScript is MigrationHelper {
    function run() public override {
        super.run();

        address parentContract = address(0xD157904639E89df05e89e0DabeEC99aE3d74F9AA); // Rewards Distributor
        address[] memory appContracts = new address[](2);

        appContracts[0] = address(0x793500709506652Fcc61F0d2D0fDa605638D4293); //Treasury

        KintoAppRegistry kintoAppRegistry = KintoAppRegistry(payable(_getChainDeployment("KintoAppRegistry")));

        uint256[4] memory appLimits = [
            kintoAppRegistry.RATE_LIMIT_PERIOD(),
            kintoAppRegistry.RATE_LIMIT_THRESHOLD(),
            kintoAppRegistry.GAS_LIMIT_PERIOD(),
            kintoAppRegistry.GAS_LIMIT_THRESHOLD()
        ];

        // Socket-batcher app
        address[] memory devEOAs = new address[](2);
        devEOAs[0] = address(0x660ad4B5A74130a4796B4d54BC6750Ae93C86e6c); // Default deployer
        devEOAs[3] = address(0x0ED31428E4bCb3cdf8A1fCD4656Ee965f4241711); // Liquidity mining relayer

        vm.startBroadcast(deployerPrivateKey);
        kintoAppRegistry.registerApp("kinto-core", parentContract, appContracts, appLimits, devEOAs);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";

contract KintoCoreAppScript is MigrationHelper {
    function run() public override {
        super.run();

        address parentContract = address(0xD157904639E89df05e89e0DabeEC99aE3d74F9AA); // Rewards Distributor
        address[] memory appContracts = new address[](3);

        appContracts[0] = address(0x793500709506652Fcc61F0d2D0fDa605638D4293); //Treasury
        appContracts[1] = address(0x8a4720488CA32f1223ccFE5A087e250fE3BC5D75); //Wallet Factory
        appContracts[2] = address(0x5A2b641b84b0230C8e75F55d5afd27f4Dbd59d5b); //App Registry

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
        devEOAs[1] = address(0x0ED31428E4bCb3cdf8A1fCD4656Ee965f4241711); // Liquidity mining relayer

        _handleOps(
            abi.encodeWithSelector(KintoAppRegistry.updateMetadata.selector, "kinto-core", parentContract, appContracts, appLimits, devEOAs),
            address(_getChainDeployment("KintoAppRegistry"))
        );
    }
}

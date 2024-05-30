// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/KintoID.sol";
import "../../src/wallet/KintoWalletFactory.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration37DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        KintoID kintoID = KintoID(_getChainDeployment("KintoID"));
        KintoWalletFactory walletFactory = KintoWalletFactory(_getChainDeployment("KintoWalletFactory"));

        // providers
        address DEFENDER_KYC_PROVIDER = 0x6E31039abF8d248aBed57E307C9E1b7530c269E4;
        uint256 previousProviderPk = vm.envUint("PRIVATE_KEY_KYC_PROVIDER");
        address previousProvider = vm.addr(previousProviderPk);

        // transfer ETH balance from previousProvider to relayer
        uint256 balance = previousProvider.balance;
        uint256 defenderBalance = DEFENDER_KYC_PROVIDER.balance;

        vm.broadcast(previousProviderPk);
        walletFactory.sendMoneyToAccount{value: balance}(DEFENDER_KYC_PROVIDER);

        assertTrue(previousProvider.balance == 0);
        assertTrue(DEFENDER_KYC_PROVIDER.balance == defenderBalance + balance);

        // revoke KYC_PROVIDER role from previous provider
        bytes32 role = kintoID.KYC_PROVIDER_ROLE();
        assertTrue(kintoID.hasRole(role, previousProvider));

        vm.broadcast();
        kintoID.revokeRole(role, previousProvider);
        assertFalse(kintoID.hasRole(role, previousProvider));
    }
}

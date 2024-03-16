// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/KintoID.sol";
import "./utils/MigrationHelper.sol";

contract KintoMigration39DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();
        address DEFENDER_KYC_PROVIDER = 0xb539019776eF803E89EC062Ad54cA24D1Fdb008a;

        address factoryAddr = _getChainDeployment("KintoWalletFactory");
        if (factoryAddr == address(0)) {
            console.log("Need to execute main deploy script first", factoryAddr);
            return;
        }

        KintoID kintoID = KintoID(_getChainDeployment("KintoID"));
        // grant KYC_PROVIDER_ROLE to relayer
        bytes32 role = kintoID.KYC_PROVIDER_ROLE();
        vm.startBroadcast();
        kintoID.grantRole(role, DEFENDER_KYC_PROVIDER);
        uint256 AMOUNT_TO_SEND = 0.1 ether;
        KintoWalletFactory(address(factoryAddr)).sendMoneyToAccount{value: AMOUNT_TO_SEND}(
            0xb539019776eF803E89EC062Ad54cA24D1Fdb008a
        );
        require(address(0xb539019776eF803E89EC062Ad54cA24D1Fdb008a).balance >= AMOUNT_TO_SEND, "amount was not sent");

        assertTrue(kintoID.hasRole(role, DEFENDER_KYC_PROVIDER));
    }
}

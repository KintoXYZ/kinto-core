// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/apps/KintoAppRegistry.sol";
import "@kinto-core/paymasters/SponsorPaymaster.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "@kinto-core-script/migrations/const.sol";

contract Script is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(
            type(SponsorPaymaster).creationCode,
            abi.encode(_getChainDeployment("EntryPoint"), _getChainDeployment("KintoWalletFactory"))
        );
        address impl = _deployImplementationAndUpgrade("SponsorPaymaster", "V14", bytecode);
        saveContractAddress("SponsorPaymasterV14-impl", impl);

        ISponsorPaymaster paymaster = ISponsorPaymaster(_getChainDeployment("SponsorPaymaster"));

        assertEq(address(paymaster.appRegistry()), _getChainDeployment("KintoAppRegistry"));
        assertEq(address(paymaster.walletFactory()), _getChainDeployment("KintoWalletFactory"));
    }
}

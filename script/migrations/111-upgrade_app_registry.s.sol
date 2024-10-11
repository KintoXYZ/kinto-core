// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/apps/KintoAppRegistry.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/console2.sol";

contract DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(
            type(KintoAppRegistry).creationCode,
            abi.encode(_getChainDeployment("KintoWalletFactory"), _getChainDeployment("SponsorPaymaster"))
        );
        address impl = _deployImplementationAndUpgrade("KintoAppRegistry", "V19", bytecode);
        saveContractAddress("KintoAppRegistryV19-impl", impl);

        KintoAppRegistry registry = KintoAppRegistry(_getChainDeployment("KintoAppRegistry"));

        assertEq(address(registry.paymaster()), _getChainDeployment("SponsorPaymaster"));
        assertEq(address(registry.walletFactory()), _getChainDeployment("KintoWalletFactory"));
        assertEq(address(registry.ENTRYPOINT_V7()), 0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ISponsorPaymaster} from "@kinto-core/interfaces/ISponsorPaymaster.sol";
import {SponsorPaymaster} from "@kinto-core/paymasters/SponsorPaymaster.sol";

import "forge-std/console2.sol";

contract DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        _whitelistApp(_getChainDeployment("SponsorPaymaster"));

        bytes memory bytecode = abi.encodePacked(
            type(SponsorPaymaster).creationCode,
            abi.encode(_getChainDeployment("EntryPoint"), _getChainDeployment("KintoWalletFactory"))
        );
        address impl = _deployImplementationAndUpgrade("SponsorPaymaster", "V11", bytecode);

        saveContractAddress("SponsorPaymasterV11-impl", impl);

        ISponsorPaymaster paymaster = ISponsorPaymaster(_getChainDeployment("SponsorPaymaster"));
        console2.log("paymaster:", address(paymaster));

        assertEq(address(paymaster.appRegistry()), _getChainDeployment("KintoAppRegistry"));
        assertEq(address(paymaster.walletFactory()), _getChainDeployment("KintoWalletFactory"));
    }
}

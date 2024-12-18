// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/apps/KintoAppRegistry.sol";
import "@kinto-core/paymasters/SponsorPaymaster.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "@kinto-core-script/migrations/const.sol";

contract Script is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode =
            abi.encodePacked(type(KintoAppRegistry).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        address impl = _deployImplementationAndUpgrade("KintoAppRegistry", "V10", bytecode);
        saveContractAddress("KintoAppRegistryV10-impl", impl);

        bytecode = abi.encodePacked(
            type(KintoWallet).creationCode,
            abi.encode(
                _getChainDeployment("EntryPoint"),
                _getChainDeployment("KintoID"),
                _getChainDeployment("KintoAppRegistry"),
                _getChainDeployment("KintoWalletFactory")
            )
        );
        impl = _deployImplementationAndUpgrade("KintoWallet", "V31", bytecode);
        saveContractAddress("KintoWalletV31-impl", impl);

        bytecode = abi.encodePacked(
            type(SponsorPaymaster).creationCode,
            abi.encode(_getChainDeployment("EntryPoint"), _getChainDeployment("KintoWalletFactory"))
        );
        _deployImplementationAndUpgrade("SponsorPaymaster", "V12", bytecode);
        saveContractAddress("SponsorPaymasterV12-impl", impl);

        address[] memory systemApps = new address[](2);
        systemApps[0] = 0x3e9727470C66B1e77034590926CDe0242B5A3dCc;
        systemApps[1] = 0xD157904639E89df05e89e0DabeEC99aE3d74F9AA;
        _handleOps(
            abi.encodeWithSelector(KintoAppRegistry.updateSystemApps.selector, systemApps),
            address(_getChainDeployment("KintoAppRegistry"))
        );
    }
}

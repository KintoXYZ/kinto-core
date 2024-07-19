// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";

contract DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode =
            abi.encodePacked(type(KintoAppRegistry).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        address impl = _deployImplementationAndUpgrade("KintoAppRegistry", "V12", bytecode);

        saveContractAddress("KintoAppRegistryV12-impl", impl);
        KintoAppRegistry kintoAppRegistry = KintoAppRegistry(payable(_getChainDeployment("KintoAppRegistry")));
        _handleOps(
            abi.encodeWithSelector(
                KintoAppRegistry.setDeployerEOA.selector,
                0xe03949063eD1E4eB8B94d5D82d1e5a21e1dd1A97,
                0x78357316239040e19fC823372cC179ca75e64b81
            ),
            address(_getChainDeployment("KintoAppRegistry"))
        );
        assertEq(kintoAppRegistry.deployerToWallet(0x78357316239040e19fC823372cC179ca75e64b81), 0xe03949063eD1E4eB8B94d5D82d1e5a21e1dd1A97);
    }
}

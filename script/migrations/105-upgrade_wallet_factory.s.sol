// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import {KintoWalletFactory} from "../../src/wallet/KintoWalletFactory.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract DeployScript is MigrationHelper {
    function run() public override {
        super.run();
        bytes memory bytecode = abi.encodePacked(
            type(KintoWalletFactory).creationCode,
            // wallet address is not used anymore
            abi.encode(address(0), _getChainDeployment("KintoAppRegistry"), _getChainDeployment("KintoID"))
        );

        address impl = _deployImplementationAndUpgrade("KintoWalletFactory", "V22", bytecode);
        saveContractAddress("KintoWalletFactoryV22-impl", impl);

        KintoWalletFactory factory = KintoWalletFactory(_getChainDeployment("KintoWalletFactory"));
        assertEq(address(factory.kintoID()), _getChainDeployment("KintoID"));
        assertEq(address(factory.appRegistry()), _getChainDeployment("KintoAppRegistry"));
    }
}

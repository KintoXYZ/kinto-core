// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/bridger/BridgerL2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "forge-std/console2.sol";

contract KintoMigration43DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode =
            abi.encodePacked(type(BridgerL2).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        address implementation = _deployImplementation("BridgerL2", "V9", bytecode);
        console2.log("implementation: %s", implementation);

        address proxy = _getChainDeployment("BridgerL2");
        console2.log("proxy: %s", proxy);
        _upgradeTo(proxy, implementation, deployerPrivateKey);

        // _deployImplementationAndUpgrade("BridgerL2", "V9", bytecode);
    }
}

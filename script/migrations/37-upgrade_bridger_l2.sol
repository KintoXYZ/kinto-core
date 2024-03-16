// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/bridger/BridgerL2.sol";
import "./utils/MigrationHelper.sol";

contract KintoMigration37DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        bytes memory bytecode =
            abi.encodePacked(type(BridgerL2).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));

        _deployImplementationAndUpgrade("BridgerL2", "V2", bytecode);
    }
}

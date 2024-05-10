// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/viewers/KYCViewer.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";

contract KYCViewerV3 is KYCViewer {
    constructor(address _kintoWalletFactory, address _faucet) KYCViewer(_kintoWalletFactory, _faucet) {}
}

contract KintoMigration23DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        // generate bytecode for KYCViewer
        bytes memory bytecode = abi.encodePacked(
            type(KYCViewerV3).creationCode,
            abi.encode(_getChainDeployment("KintoWalletFactory"), _getChainDeployment("Faucet"))
        );

        // upgrade KYCViewer to V3
        _deployImplementationAndUpgrade("KYCViewer", "V3", bytecode);
    }
}

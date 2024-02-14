// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../src/viewers/KYCViewer.sol";
import "./utils/MigrationHelper.sol";

contract KintoMigration25DeployScript is MigrationHelper {
    using MessageHashUtils for bytes32;

    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(
            type(KYCViewer).creationCode,
            abi.encode(_getChainDeployment("KintoWalletFactory"), _getChainDeployment("Faucet"))
        );
        address implementation = _deployImplementation("KYCViewer", "V4", bytecode);
        address proxy = _deployProxy("KYCViewer", implementation);

        _whitelistApp(proxy, deployerPrivateKey);
        _initialize(proxy, deployerPrivateKey);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/inflators/KintoInflator.sol";
import "./utils/MigrationHelper.sol";

contract KintoMigration30DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        /// @dev since KintoInflator is owned by the ledger, we can't upgrade so we are both the implementation and the proxy
        bytes memory bytecode = abi.encodePacked(type(KintoInflator).creationCode);
        address implementation = _deployImplementation("KintoInflator", "V1", bytecode);
        address proxy = _deployProxy("KintoInflator", implementation);

        // remove the old KintoInflator from the whitelist
        _whitelistApp(_getChainDeployment("KintoInflator"), deployerPrivateKey, false);

        // whitelist the new KintoInflator & initialize
        _whitelistApp(proxy, deployerPrivateKey);
        _initialize(proxy, deployerPrivateKey);
    }
}

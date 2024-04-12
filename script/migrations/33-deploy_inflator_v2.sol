// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/inflators/KintoInflator.sol";
import "./utils/MigrationHelper.sol";

contract KintoMigration33DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(type(KintoInflator).creationCode);
        _deployImplementationAndUpgrade("KintoInflator", "V2", bytecode);

        // transfer ownership to LEDGER_ADMIN
        address inflator = _getChainDeployment("KintoInflator");
        _handleOps(
            abi.encodeWithSelector(Ownable.transferOwnership.selector, vm.envAddress("LEDGER_ADMIN")),
            inflator,
            deployerPrivateKey
        );
        assertEq(KintoInflator(inflator).owner(), vm.envAddress("LEDGER_ADMIN"));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/tokens/EngenBadges.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "@kinto-core-script/migrations/const.sol";

contract KintoMigration73DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(type(EngenBadges).creationCode);
        address implementation = _deployImplementation("EngenBadges", "V2", bytecode);

        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = LEDGER;

        _handleOps(
            abi.encodeWithSelector(UUPSUpgradeable.upgradeTo.selector, address(implementation)),
            _getChainDeployment("KintoWallet-admin"),
            _getChainDeployment("EngenBadges"),
            0,
            address(0),
            privKeys
        );
    }
}

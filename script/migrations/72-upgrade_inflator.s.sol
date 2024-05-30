// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/inflators/KintoInflator.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "@kinto-core-script/migrations/const.sol";

contract KintoMigration72DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(type(KintoInflator).creationCode);
        address implementation = _deployImplementation("KintoInflator", "V3", bytecode);

        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = LEDGER;

        _handleOps(
            abi.encodeWithSelector(UUPSUpgradeable.upgradeTo.selector, address(implementation)),
            _getChainDeployment("KintoWallet-admin"),
            _getChainDeployment("KintoInflator"),
            0,
            address(0),
            privKeys
        );
    }
}

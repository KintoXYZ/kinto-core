// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/inflators/KintoInflator.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";
import "@kinto-core-script/migrations/const.sol";

contract KintoMigration72DeployScript is MigrationHelper, Constants {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(type(KintoInflator).creationCode);
        address implementation = _deployImplementation("KintoInflator", "V3", bytecode);

        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = LEDGER;

        // upgradeTo
        _handleOps(
            abi.encodeWithSelector(UUPSUpgradeable.upgradeTo.selector, address(implementation)),
            payable(_getChainDeployment("KintoWallet-admin")),
            _getChainDeployment("KintoInflator"),
            address(0),
            privKeys
        );
    }
}

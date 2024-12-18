// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/bridger/BridgerL2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration35DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode =
            abi.encodePacked(type(BridgerL2).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        address implementation = _deployImplementation("BridgerL2", "V1", bytecode);
        address proxy = _deployProxy("BridgerL2", implementation);

        _whitelistApp(proxy);
        _initialize(proxy, deployerPrivateKey);
        // _transferOwnership(proxy, deployerPrivateKey, vm.envAddress("LEDGER_ADMIN"));
        assertEq(address(BridgerL2(proxy).walletFactory()), vm.envAddress("KINTO_WALLET_FACTORY"));
        assertEq(BridgerL2(proxy).owner(), 0x2e2B1c42E38f5af81771e65D87729E57ABD1337a);
    }
}

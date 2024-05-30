// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/bridger/BridgerL2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "forge-std/console2.sol";

contract KintoMigration61DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode =
            abi.encodePacked(type(BridgerL2).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        address implementation = _deployImplementation("BridgerL2", "V10", bytecode);
        console2.log("implementation: %s", implementation);

        address proxy = _getChainDeployment("BridgerL2");
        console2.log("proxy: %s", proxy);
        _upgradeTo(proxy, implementation, deployerPrivateKey);

        // set deposited assets (adding ENA)
        address[] memory assets = new address[](5);
        assets[0] = 0x4190A8ABDe37c9A85fAC181037844615BA934711; // sDAI
        assets[1] = 0xF4d81A46cc3fCA44f88d87912A35E7fCC4B398ee; // sUSDe
        assets[2] = 0x6e316425A25D2Cf15fb04BCD3eE7c6325B240200; // wstETH
        assets[3] = 0xC60F14d95B87417BfD17a376276DE15bE7171d31; // weETH
        assets[4] = 0xE040001C257237839a69E9683349C173297876F0; // ENA

        bytes memory selectorAndParams = abi.encodeWithSelector(BridgerL2.setDepositedAssets.selector, assets);
        _handleOps(selectorAndParams, proxy, deployerPrivateKey);
    }
}

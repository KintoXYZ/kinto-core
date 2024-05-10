// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/interfaces/IFaucet.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";

contract StartFaucetScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory selectorAndParams = abi.encodeWithSelector(IFaucet.startFaucet.selector);
        _handleOps(selectorAndParams, _getChainDeployment("Faucet"), deployerPrivateKey);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../src/interfaces/IFaucet.sol";
import "./migrations/utils/MigrationHelper.sol";

contract StartFaucetScript is MigrationHelper {
    using MessageHashUtils for bytes32;

    function run() public override {
        super.run();

        bytes memory selectorAndParams = abi.encodeWithSelector(IFaucet.startFaucet.selector);
        _handleOps(selectorAndParams, _getChainDeployment("Faucet"), deployerPrivateKey);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/bridger/BridgerL2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "forge-std/console2.sol";

contract UpgradeBridgerL2Script is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(
            type(BridgerL2).creationCode,
            abi.encode(_getChainDeployment("KintoWalletFactory"), _getChainDeployment("KintoID"))
        );

        address impl = _deployImplementationAndUpgrade("BridgerL2", "V13", bytecode);

        BridgerL2 bridgerL2 = BridgerL2(payable(_getChainDeployment("BridgerL2")));

        assertEq(address(bridgerL2.walletFactory()), _getChainDeployment("KintoWalletFactory"));
        assertEq(address(bridgerL2.kintoID()), _getChainDeployment("KintoID"));

        saveContractAddress("BridgerL2V13-impl", impl);
    }
}

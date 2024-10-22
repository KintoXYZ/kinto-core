// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Faucet} from "../../src/Faucet.sol";
import {KintoID} from "../../src/KintoID.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract UpgradeKintoIDFaucetDeployScript is MigrationHelper {
    function run() public override {
        super.run();

        // bytes memory bytecode = abi.encodePacked(
        //     type(KintoID).creationCode,
        //     abi.encode(
        //         _getChainDeployment("KintoWalletFactory"),
        //         _getChainDeployment("Faucet")
        //     )
        // );

        // address impl = _deployImplementationAndUpgrade("KintoID", "V8", bytecode);
        // saveContractAddress("KintoIDV8-impl", impl);

        // bytecode = abi.encodePacked(
        //     type(Faucet).creationCode,
        //     abi.encode(_getChainDeployment("KintoWalletFactory"))
        // );

        // impl = _deployImplementationAndUpgrade("Faucet", "V9", bytecode);
        // saveContractAddress("FaucetV9-impl", impl);

        // vm.broadcast(deployerPrivateKey);
        KintoID kintoID = KintoID(_getChainDeployment("KintoID"));
        _whitelistApp(address(kintoID));
        _upgradeTo(address(kintoID), _getChainDeployment("KintoIDV8-impl"), deployerPrivateKey);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {BridgedToken} from "@kinto-core/tokens/bridged/BridgedToken.sol";
import {BridgedSol} from "@kinto-core/tokens/bridged/BridgedSol.sol";
import {UUPSUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract UpgradeBridgedSolScript is MigrationHelper {
    BridgedSol sol;

    function run() public override {
        super.run();

        sol = BridgedSol(payable(_getChainDeployment("SOL")));
        if (address(sol) == address(0)) {
            console2.log("SOL has to be deployed");
            return;
        }

        // vm.broadcast(deployerPrivateKey);
        bytes memory bytecode = abi.encodePacked(type(BridgedSol).creationCode);

        _deployImplementationAndUpgrade("SOL", "V2", bytecode);

        require(sol.decimals() == 9, "SOL upgrade failed");
    }
}

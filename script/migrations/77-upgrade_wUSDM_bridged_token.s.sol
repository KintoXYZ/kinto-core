// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";

import {BridgedWusdm} from "@kinto-core/tokens/bridged/BridgedWUSDM.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {Constants} from "@kinto-core-script/migrations/const.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

import {console2} from "forge-std/console2.sol";

contract KintoMigration77DeployScript is MigrationHelper {
    using LibString for *;

    function run() public override {
        super.run();

        // deploy token
        bytes memory bytecode = abi.encodePacked(
            type(BridgedWusdm).creationCode,
            abi.encode(18, _getChainDeployment("KintoWalletFactory"), _getChainDeployment("KintoID"))
        );
        address proxy = _getChainDeployment("wUSDM");
        address impl = _deployImplementationAndUpgrade("wUSDM", "V2", bytecode);

        BridgedWusdm bridgedToken = BridgedWusdm(proxy);
        require(bridgedToken.decimals() == 18, "Decimals mismatch");

        console2.log("All checks passed!");

        console2.log("implementation deployed @%s", impl);

        saveContractAddress(string.concat(bridgedToken.symbol(), "V2", "-impl"), impl);
    }
}

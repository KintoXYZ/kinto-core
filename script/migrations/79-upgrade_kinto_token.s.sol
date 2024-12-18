// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";

import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {Constants} from "@kinto-core-script/migrations/const.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";

import {console2} from "forge-std/console2.sol";

contract KintoMigration79DeployScript is MigrationHelper {
    using LibString for *;
    using Strings for string;

    function run() public override {
        super.run();

        vm.startBroadcast(deployerPrivateKey);
        console2.log("Executing with address", msg.sender);
        // deploy token
        address impl = address(new BridgedKinto{salt: keccak256(abi.encodePacked("K"))}());
        vm.stopBroadcast();
        vm.startBroadcast();
        address proxy = _getChainDeployment("KINTO");

        BridgedKinto bridgedToken = BridgedKinto(proxy);
        _upgradeTo(proxy, impl, deployerPrivateKey);

        require(bridgedToken.decimals() == 18, "Decimals mismatch");
        require(bridgedToken.symbol().equal("K"), "");
        require(bridgedToken.name().equal("Kinto Token"), "");

        console2.log("All checks passed!");
        console2.log("implementation deployed @%s", impl);

        saveContractAddress(string.concat(bridgedToken.symbol(), "V2", "-impl"), impl);
    }
}

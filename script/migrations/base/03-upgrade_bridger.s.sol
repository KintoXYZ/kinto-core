// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {Bridger} from "@kinto-core/bridger/Bridger.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

import {Constants} from "@kinto-core-script/migrations/arbitrum/const.sol";

contract UpgradeBridgerScript is Constants, Test, MigrationHelper {
    function run() public override {
        super.run();

        vm.startBroadcast(deployerPrivateKey);
        Bridger bridger = Bridger(payable(_getChainDeployment("Bridger")));
        bridger.upgradeTo(0x49B3ca4A91F5aF84855A9dd2E27EFeb3D693Cb3d);
        bridger.transferOwnership(0x45e9deAbb4FdD048Ae38Fce9D9E8d68EC6f592a2);

        // Checks
        assertEq(bridger.owner(), 0x45e9deAbb4FdD048Ae38Fce9D9E8d68EC6f592a2, "Invalid owner");
    }
}
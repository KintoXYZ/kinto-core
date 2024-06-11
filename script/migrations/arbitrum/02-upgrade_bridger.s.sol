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

        bytes memory bytecode = abi.encodePacked(
            type(Bridger).creationCode,
            abi.encode(EXCHANGE_PROXY, CURVE_USDM_POOL, USDC, WETH, address(0), address(0), address(0), address(0))
        );

        address newImpl = _deployImplementationAndUpgrade("Bridger", "V3", bytecode);

        // Checks
        Bridger bridger = Bridger(payable(_getChainDeployment("Bridger")));

        assertEq(bridger.senderAccount(), SENDER_ACCOUNT, "Invalid Sender Account");
        assertEq(bridger.owner(), deployer, "Invalid Owner");
        console.log("BridgerV3-impl at: %s", address(newImpl));
    }
}

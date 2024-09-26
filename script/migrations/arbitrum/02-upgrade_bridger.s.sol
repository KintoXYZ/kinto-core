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

        if (block.chainid != ARBITRUM_CHAINID) {
            console2.log("This script is meant to be run on the chain: %s", ARBITRUM_CHAINID);
            return;
        }

        Bridger bridger = Bridger(payable(_getChainDeployment("Bridger")));

        vm.broadcast(deployerPrivateKey);
        address newImpl =
            address(new Bridger(EXCHANGE_PROXY, USDC, WETH, address(0), address(0), address(0), address(0)));

        vm.prank(bridger.owner());
        bridger.upgradeTo(newImpl);

        // Checks
        assertEq(bridger.senderAccount(), 0x89A01e3B2C3A16c3960EADc2ceFcCf2D3AA3F82e, "Invalid Sender Account");
        assertEq(bridger.owner(), MAMORI_SAFE, "Invalid Owner");
        assertEq(bridger.SOLV_BTC(), 0x3647c54c4c2C65bC7a2D63c0Da2809B399DBBDC0, "Invalid SolvBtc address");

        // Save address
        saveContractAddress("BridgerV11-impl", newImpl);
    }
}

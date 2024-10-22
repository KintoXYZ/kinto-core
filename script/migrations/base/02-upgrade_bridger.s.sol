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

import {Constants} from "@kinto-core-script/migrations/base/const.sol";

contract UpgradeBridgerScript is Constants, Test, MigrationHelper {
    function run() public override {
        super.run();

        if (block.chainid != BASE_CHAINID) {
            console2.log("This script is meant to be run on the chain: %s", BASE_CHAINID);
            return;
        }

        Bridger bridger = Bridger(payable(_getChainDeployment("Bridger")));

        // Set DAI to zero, as it has a normal `permit` on Base.
        // Set wstEth to zero, as staking is not supported on Base.
        // Set USDe and sUSDe to zero, as staking USDe is not supported on Base.
        // Set Curve pool and USDC to zero as we do not support USDM on Base.
        vm.broadcast(deployerPrivateKey);
        address newImpl =
            address(new Bridger(EXCHANGE_PROXY, address(0), WETH, address(0), address(0), address(0), address(0)));

        vm.prank(bridger.owner());
        bridger.upgradeTo(address(newImpl));

        // Checks
        assertEq(bridger.senderAccount(), SENDER_ACCOUNT, "Invalid Sender Account");
        // Mamori Safe
        assertEq(bridger.owner(), 0x45e9deAbb4FdD048Ae38Fce9D9E8d68EC6f592a2, "Invalid Owner");
        saveContractAddress("BridgerV6-impl", newImpl);
    }
}

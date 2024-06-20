// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/bridger/Bridger.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

import {Constants} from "@kinto-core-script/migrations/base/const.sol";

contract DeployBridgerScript is Constants, Test, MigrationHelper {
    Bridger internal bridger;
    address internal impl;

    function run() public override {
        super.run();

        if (block.chainid != BASE_CHAINID) {
            console2.log("This script is meant to be run on the chain: %s", BASE_CHAINID);
            return;
        }
        address bridgerAddress = _getChainDeployment("Bridger", BASE_CHAINID);
        if (bridgerAddress != address(0)) {
            console2.log("Already deployed bridger", bridgerAddress);
            return;
        }

        // Set DAI to zero, as it has a normal `permit` on Base.
        // Set wstEth to zero, as staking is not supported on Base.
        // Set USDe and sUSDe to zero, as staking USDe is not supported on Base.
        impl = create2(
            abi.encodePacked(
                type(Bridger).creationCode,
                abi.encode(EXCHANGE_PROXY, address(0), address(0), WETH, address(0), address(0), address(0), address(0))
            )
        );
        console2.log("Bridger implementation deployed at", address(impl));
        // deploy proxy contract and point it to implementation
        address proxy = create2(abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(address(impl), "")));
        bridger = Bridger(payable(address(proxy)));
        console2.log("Bridger proxy deployed at ", address(bridger));
        // Initialize proxy
        bridger.initialize(SENDER_ACCOUNT);

        // Checks
        assertEq(bridger.senderAccount(), SENDER_ACCOUNT, "Invalid Sender Account");
        assertEq(bridger.owner(), deployer, "Invalid Owner");
    }
}

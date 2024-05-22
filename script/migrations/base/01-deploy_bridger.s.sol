// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/bridger/Bridger.sol";

import {DeployerHelper} from "@kinto-core/libraries/DeployerHelper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

import {Constants} from "@kinto-core-script/migrations/base/const.sol";

contract DeployBridgerScript is ArtifactsReader, DeployerHelper, Test, Constants {
    Bridger internal bridger;
    address internal impl;

    function setUp() public {}

    function deployContracts(address) internal override {
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
            "BridgerV1-impl",
            abi.encodePacked(
                type(Bridger).creationCode,
                abi.encode(L2_VAULT, EXCHANGE_PROXY, WETH, address(0), address(0), address(0), address(0))
            )
        );
        console2.log("Bridger implementation deployed at", address(impl));
        // deploy proxy contract and point it to implementation
        address proxy =
            create2("Bridger", abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(address(impl), "")));
        bridger = Bridger(payable(address(proxy)));
        console2.log("Bridger proxy deployed at ", address(bridger));
        // Initialize proxy
        bridger.initialize(SENDER_ACCOUNT);
    }

    function checkContracts(address deployer) internal view override {
        // Checks
        assertEq(bridger.senderAccount(), SENDER_ACCOUNT, "Invalid Sender Account");
        assertEq(bridger.l2Vault(), L2_VAULT, "Invalid L2 Vault");
        assertEq(bridger.owner(), deployer, "Invalid Owner");
    }
}

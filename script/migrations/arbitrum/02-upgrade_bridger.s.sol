// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/bridger/Bridger.sol";

import {DeployerHelper} from "@kinto-core/libraries/DeployerHelper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

import {Constants} from "@kinto-core-script/migrations/arbitrum/const.sol";

contract UpgradeBridgerScript is ArtifactsReader, DeployerHelper, Test, Constants {
    Bridger internal bridger;
    address internal newImpl;
    address internal bridgerAddress;

    function setUp() public {}

    function deployContracts(address) internal override {
        bridgerAddress = _getChainDeployment("Bridger", ARBITRUM_CHAINID);
        if (bridgerAddress == address(0)) {
            console.log("Not deployed bridger", bridgerAddress);
            return;
        }

        // Deploy implementation
        newImpl = create2(
            "BridgerV2-impl",
            abi.encodePacked(
                type(Bridger).creationCode, abi.encode(L2_VAULT, EXCHANGE_PROXY, WETH, address(0), address(0), address(0), address(0))
            )
        );
        bridger = Bridger(payable(bridgerAddress));
        bridger.upgradeTo(address(newImpl));
    }

    function checkContracts(address deployer) internal override {
        // Checks
        assertEq(bridger.senderAccount(), SENDER_ACCOUNT, "Invalid Sender Account");
        assertEq(bridger.l2Vault(), L2_VAULT, "Invalid L2 Vault");
        assertEq(bridger.owner(), deployer, "Invalid Owner");
        console.log("BridgerV2-impl at: %s", address(newImpl));
    }
}

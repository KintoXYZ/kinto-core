// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/bridger/Bridger.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

import {Constants} from "@kinto-core-script/migrations/mainnet/const.sol";

contract UpgradeBridgerScript is Constants, Test, MigrationHelper {
    Bridger internal bridger;
    address internal newImpl;
    address internal bridgerAddress;

    function setUp() public {}

    function run() public override {
        super.run();

        bridgerAddress = _getChainDeployment("Bridger", 1);
        if (bridgerAddress == address(0)) {
            console.log("Not deployed bridger", bridgerAddress);
            return;
        }

        // Deploy implementation
        vm.broadcast(deployerPrivateKey);
        newImpl = address(new Bridger(EXCHANGE_PROXY, address(0), WETH, DAI, USDe, sUSDe, wstETH));
        // Stop broadcast because the Owner is Safe account

        bridger = Bridger(payable(bridgerAddress));
        vm.prank(bridger.owner());
        bridger.upgradeTo(newImpl);

        // Checks
        assertEq(bridger.senderAccount(), 0x89A01e3B2C3A16c3960EADc2ceFcCf2D3AA3F82e, "Invalid Sender Account");
        // Safe Account
        assertEq(bridger.owner(), 0xf152Abda9E4ce8b134eF22Dc3C6aCe19C4895D82, "Invalid Owner");

        saveContractAddress("BridgerV12-impl", newImpl);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/bridger/Bridger.sol";

import {DeployerHelper} from "@kinto-core/libraries/DeployerHelper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

import {Constants} from "@kinto-core-script/migrations/mainnet/const.sol";

contract UpgradeBridgerScript is ArtifactsReader, DeployerHelper, Test, Constants {
    Bridger internal bridger;
    address internal newImpl;
    address internal bridgerAddress;

    function setUp() public {}

    function deployContracts(address) internal override {
        bridgerAddress = _getChainDeployment("Bridger", 1);
        if (bridgerAddress == address(0)) {
            console.log("Not deployed bridger", bridgerAddress);
            return;
        }

        // Deploy implementation
        newImpl = create2(
            "BridgerV6-impl",
            abi.encodePacked(
                type(Bridger).creationCode, abi.encode(L2_VAULT, EXCHANGE_PROXY, WETH, DAI, USDe, sUSDe, wstETH)
            )
        );
        // Stop broadcast because the Owner is Safe account
    }

    function checkContracts(address) internal override {
        bridger = Bridger(payable(bridgerAddress));
        vm.prank(bridger.owner());
        bridger.upgradeTo(address(newImpl));

        // Checks
        assertEq(bridger.senderAccount(), 0x89A01e3B2C3A16c3960EADc2ceFcCf2D3AA3F82e, "Invalid Sender Account");
        assertEq(bridger.l2Vault(), 0x26181Dfc530d96523350e895180b09BAf3d816a0, "Invalid L2 Vault");
        // Safe Account
        assertEq(bridger.owner(), 0xf152Abda9E4ce8b134eF22Dc3C6aCe19C4895D82, "Invalid Owner");

        console.log("BridgerV6-impl at: %s", address(newImpl));
    }
}

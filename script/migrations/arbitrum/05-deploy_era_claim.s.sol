pragma solidity ^0.8.24;

import {StakerClaim} from "@kinto-core/vaults/StakerClaim.sol";

import {Create2Helper} from "@kinto-core-test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {DeployerHelper} from "@kinto-core-script/utils/DeployerHelper.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

contract DeployStakerClaimScript is Test, MigrationHelper {

    function setUp() public {}

    function run() public override {
        super.run();

        if (block.chainid != ARBITRUM_CHAINID) {
            console.log("This script is meant to be run on arbitrum");
            return;
        }

        vm.broadcast(deployerPrivateKey);
        StakerClaim kovr = new StakerClaim();

        // Checks
        assertEq(address(kovr.USDC()), 0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
        assertEq(address(kovr.KINTO()), 0x6bA19Ee69D5DDe3aB70185C801fA404F66feDB58);
        assertEq(kovr.OWNER(), 0x8bFe32Ac9C21609F45eE6AE44d4E326973700614);

        saveContractAddress("StakerClaim", address(kovr));
    }
}

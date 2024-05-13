// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../../src/tokens/KintoToken.sol";
import "../../../src/tokens/VestingContract.sol";

import "../../../test/helpers/Create2Helper.sol";
import "../../../test/helpers/ArtifactsReader.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

contract KintoMainnetMigration1DeployScript is Create2Helper, ArtifactsReader, Test {
    KintoToken _token;
    VestingContract _vestingContract;

    function setUp() public {}

    function run() public {
        if (block.chainid != 1) {
            console.log("This script is meant to be run on the mainnet");
            return;
        }
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // If not using ledger, replace
        console.log("Executing with address", msg.sender);
        vm.startBroadcast();
        address kintoTokenAddress = _getChainDeployment("KintoToken", 1);
        if (kintoTokenAddress != address(0)) {
            console.log("Already deployed token", kintoTokenAddress);
            return;
        }
        address vestingContractAddress = _getChainDeployment("VestingContract", 1);
        if (vestingContractAddress != address(0)) {
            console.log("Already deployed vesting contract", vestingContractAddress);
            return;
        }

        // SAFEs addresses
        address panamaSafe = 0x4108162ADC07c627eb575c6e54a00F898c7b3e18;
        address mamoriSafe = 0xf152Abda9E4ce8b134eF22Dc3C6aCe19C4895D82;

        _token = new KintoToken();
        _vestingContract = new VestingContract(address(_token));
        _vestingContract.transferOwnership(mamoriSafe);
        _token.setVestingContract(address(_vestingContract));
        _token.transfer(address(_vestingContract), _token.SEED_TOKENS());
        _token.transferOwnership(0x4108162ADC07c627eb575c6e54a00F898c7b3e18);

        // Checks
        assertEq(_token.balanceOf(address(_vestingContract)), _token.SEED_TOKENS());
        assertEq(_token.totalSupply(), _token.SEED_TOKENS());
        assertEq(_token.balanceOf(msg.sender), 0);
        assertEq(_token.owner(), panamaSafe);
        assertEq(_vestingContract.LOCK_PERIOD(), 365 days);
        assertEq(_vestingContract.owner(), mamoriSafe);
        assertEq(_vestingContract.totalAllocated(), 0);

        vm.stopBroadcast();

        // Writes the addresses to a file
        console.log("Add these addresses to the artifacts mainnet file");
        console.log(string.concat('"KintoToken": "', vm.toString(address(_token)), '"'));
        console.log(string.concat('"VestingContract": "', vm.toString(address(_vestingContract)), '"'));
    }
}

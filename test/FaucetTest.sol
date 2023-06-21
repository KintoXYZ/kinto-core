// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/Faucet.sol";
import "src/interfaces/IFaucet.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";


contract FaucetTest is Test {
    Faucet faucet;


    address owner = address(1);
    address kyc_provider = address(2);
    address user = vm.addr(3);
    address user2 = address(4);

    function setUp() public {
        vm.chainId(42888);
        vm.startPrank(owner);
        faucet = new Faucet();
        vm.stopPrank();
    }

    function testUp() public {
        assertEq(faucet.CLAIM_AMOUNT(), 1 ether / 200);
        assertEq(faucet.FAUCET_AMOUNT(), 1 ether);
    }

    // Upgrade Tests

    function testOwnerCanStartFaucet() public {
        vm.startPrank(owner);
        faucet.startFaucet{value: 1 ether}();
        vm.stopPrank();
    }

    function testFailOwnerCannotStartWithoutAmount() public {
        vm.startPrank(owner);
        faucet.startFaucet{value: 0.1 ether}();
        vm.stopPrank();
    }

    function testFailStartFaucetByOthers() public {
        vm.startPrank(user);
        faucet.startFaucet{value: 1 ether}();
        vm.stopPrank();
    }

}

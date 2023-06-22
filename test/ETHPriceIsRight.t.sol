// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/ETHPriceIsRight.sol";
import "src/interfaces/IETHPriceIsRight.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";


contract ETHPriceIsRightTest is Test {
    ETHPriceIsRight priceIsRight;

    address owner = address(1);
    address kyc_provider = address(2);
    address user = vm.addr(3);
    address user2 = address(4);

    function setUp() public {
        vm.chainId(42888);
        vm.startPrank(owner);
        priceIsRight = new ETHPriceIsRight();
        vm.stopPrank();
    }

    function testUp() public {
        assertEq(priceIsRight.END_ENTER_TIMESTAMP(), 1735689601);
        assertEq(priceIsRight.guessCount(), 0);
        assertEq(priceIsRight.avgGuess(), 0);
        assertEq(priceIsRight.minGuess(), 0);
        assertEq(priceIsRight.maxGuess(), 0);
    }

    // Upgrade Tests

    function testAnyoneCanEnterGuessBeforeEnd() public {
        vm.startPrank(user);
        priceIsRight.enterGuess(4000 ether);
        assertEq(priceIsRight.guessCount(), 1);
        assertEq(priceIsRight.minGuess(), 4000 ether);
        assertEq(priceIsRight.maxGuess(), 4000 ether);
        assertEq(priceIsRight.avgGuess(), 4000 ether);
        vm.stopPrank();
    }

    function testAnyoneCanChangeGuessBeforeEnd() public {
        vm.startPrank(user);
        priceIsRight.enterGuess(4000 ether);
        priceIsRight.enterGuess(2000 ether);
        assertEq(priceIsRight.guessCount(), 1);
        assertEq(priceIsRight.minGuess(), 2000 ether);
        assertEq(priceIsRight.maxGuess(), 4000 ether);
        assertEq(priceIsRight.avgGuess(), 2000 ether);
        vm.stopPrank();
    }

    function testGuessCalculations() public {
        vm.startPrank(user);
        priceIsRight.enterGuess(4000 ether);
        vm.stopPrank();
        vm.startPrank(user2);
        priceIsRight.enterGuess(2000 ether);
        vm.stopPrank();
        assertEq(priceIsRight.guessCount(), 2);
        assertEq(priceIsRight.minGuess(), 2000 ether);
        assertEq(priceIsRight.maxGuess(), 4000 ether);
        assertEq(priceIsRight.avgGuess(), 3000 ether);
    }

    function testFailCannotEnterGuessAfterTime() public {
        vm.startPrank(user);
        vm.warp(priceIsRight.END_ENTER_TIMESTAMP() + 1);
        priceIsRight.enterGuess(2000 ether);
        vm.stopPrank();
    }
}

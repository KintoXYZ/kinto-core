// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/sample/ETHPriceIsRight.sol";
import "../src/interfaces/IETHPriceIsRight.sol";

contract ETHPriceIsRightTest is Test {
    ETHPriceIsRight _priceIsRight;

    address _owner = address(1);
    address _user = vm.addr(3);
    address _user2 = vm.addr(4);

    function setUp() public {
        vm.startPrank(_owner);
        _priceIsRight = new ETHPriceIsRight();
        vm.stopPrank();
    }

    function testUp() public {
        assertEq(_priceIsRight.END_ENTER_TIMESTAMP(), 1735689601);
        assertEq(_priceIsRight.guessCount(), 0);
        assertEq(_priceIsRight.avgGuess(), 0);
        assertEq(_priceIsRight.minGuess(), 0);
        assertEq(_priceIsRight.maxGuess(), 0);
    }

    // Upgrade Tests

    function testAnyoneCanEnterGuessBeforeEnd() public {
        vm.startPrank(_user);
        _priceIsRight.enterGuess(4000 ether);
        assertEq(_priceIsRight.guessCount(), 1);
        assertEq(_priceIsRight.minGuess(), 4000 ether);
        assertEq(_priceIsRight.maxGuess(), 4000 ether);
        assertEq(_priceIsRight.avgGuess(), 4000 ether);
        vm.stopPrank();
    }

    function testAnyoneCanChangeGuessBeforeEnd() public {
        vm.startPrank(_user);
        _priceIsRight.enterGuess(4000 ether);
        _priceIsRight.enterGuess(2000 ether);
        assertEq(_priceIsRight.guessCount(), 1);
        assertEq(_priceIsRight.minGuess(), 2000 ether);
        assertEq(_priceIsRight.maxGuess(), 4000 ether);
        assertEq(_priceIsRight.avgGuess(), 2000 ether);
        vm.stopPrank();
    }

    function testGuessCalculations() public {
        vm.startPrank(_user);
        _priceIsRight.enterGuess(4000 ether);
        vm.stopPrank();
        vm.startPrank(_user2);
        _priceIsRight.enterGuess(2000 ether);
        vm.stopPrank();
        assertEq(_priceIsRight.guessCount(), 2);
        assertEq(_priceIsRight.minGuess(), 2000 ether);
        assertEq(_priceIsRight.maxGuess(), 4000 ether);
        assertEq(_priceIsRight.avgGuess(), 3000 ether);
    }

    function test_RevertWhen_CannotEnterGuessAfterTime() public {
        vm.warp(_priceIsRight.END_ENTER_TIMESTAMP() + 1);

        vm.expectRevert("You cannot enter guesses anymore");
        _priceIsRight.enterGuess(2000 ether);
    }
}

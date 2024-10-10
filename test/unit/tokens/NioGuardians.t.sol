// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";
import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";
import {NioGuardians} from "@kinto-core/tokens/NioGuardians.sol";

contract NioGuardiansTest is SharedSetup {
    NioGuardians public nioGuardians;

    function setUp() public override {
        super.setUp();
        nioGuardians = new NioGuardians(admin);
    }

    function testMint() public {
        vm.prank(admin);
        nioGuardians.mint(alice, 1);

        assertEq(nioGuardians.exists(1), true);
        assertEq(nioGuardians.ownerOf(1), alice);
        assertEq(nioGuardians.balanceOf(alice), 1);
        assertEq(nioGuardians.getVotes(alice), 1);
    }

    function testBurn() public {
        vm.prank(admin);
        nioGuardians.mint(alice, 1);

        vm.prank(admin);
        nioGuardians.burn(1);

        assertEq(nioGuardians.exists(1), false);

        assertEq(nioGuardians.balanceOf(alice), 0);
        assertEq(nioGuardians.getVotes(alice), 0);
    }

    function testOnlyOwnerCanMintAndBurn() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        nioGuardians.mint(alice, 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        nioGuardians.burn(1);
    }

    function testNoTransfer() public {
        vm.prank(admin);
        nioGuardians.mint(alice, 1);
        vm.prank(alice);
        vm.expectRevert(NioGuardians.OnlyMintOrBurn.selector);
        nioGuardians.transferFrom(alice, bob, 1);
    }

    function testNoDelegate() public {
        vm.prank(admin);
        nioGuardians.mint(alice, 1);

        vm.prank(alice);
        vm.expectRevert(NioGuardians.NoDelegate.selector);
        nioGuardians.delegate(bob);

        vm.prank(alice);
        vm.expectRevert(NioGuardians.NoDelegate.selector);
        nioGuardians.delegateBySig(bob, 0, 0, 0, bytes32(0), bytes32(0));
    }

    function testVotingPower() public {
        vm.prank(admin);
        nioGuardians.mint(alice, 1);
        vm.prank(admin);
        nioGuardians.mint(alice, 2);
        vm.prank(admin);
        nioGuardians.mint(bob, 3);

        assertEq(nioGuardians.getVotes(alice), 2);
        assertEq(nioGuardians.getVotes(bob), 1);

        vm.prank(admin);
        nioGuardians.burn(1);
        assertEq(nioGuardians.getVotes(alice), 1);
    }

    function testExists() public {
        assertFalse(nioGuardians.exists(1));
        vm.prank(admin);
        nioGuardians.mint(alice, 1);
        assertTrue(nioGuardians.exists(1));
        vm.prank(admin);
        nioGuardians.burn(1);
        assertFalse(nioGuardians.exists(1));
    }

    function testClockAndClockMode() public {
        assertEq(nioGuardians.clock(), block.timestamp);
        assertEq(nioGuardians.CLOCK_MODE(), "mode=timestamp");
    }

    function testTransferBetweenUsers() public {
        vm.prank(admin);
        nioGuardians.mint(alice, 1);
        vm.prank(alice);
        vm.expectRevert(NioGuardians.OnlyMintOrBurn.selector);
        nioGuardians.transferFrom(alice, bob, 1);
    }

    function testSafeTransferBetweenUsers() public {
        vm.prank(admin);
        nioGuardians.mint(alice, 1);
        vm.prank(alice);
        vm.expectRevert(NioGuardians.OnlyMintOrBurn.selector);
        nioGuardians.safeTransferFrom(alice, bob, 1);
    }

    function testDelegateToSelf() public {
        vm.prank(admin);
        nioGuardians.mint(alice, 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NioGuardians.NoDelegate.selector));
        nioGuardians.delegate(alice);
    }
}

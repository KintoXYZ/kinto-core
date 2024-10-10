// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";

contract BridgedKintoTest is SharedSetup {
    address minter;
    address upgrader;

    BridgedKinto internal token;

    function setUp() public override {
        super.setUp();

        minter = createUser("minter");
        upgrader = createUser("upgrader");

        token = BridgedKinto(payable(address(new UUPSProxy(address(new BridgedKinto()), ""))));
        token.initialize("KINTO TOKEN", "KINTO", admin, minter, upgrader);

        vm.prank(minter);
        token.mint(_user, 500);
    }

    function setUpChain() public virtual override {
        setUpKintoLocal();
    }

    function testUp() public override {
        super.testUp();

        token = BridgedKinto(payable(address(new UUPSProxy(address(new BridgedKinto()), ""))));
        token.initialize("Kinto Token", "K", admin, minter, upgrader);

        assertEq(token.totalSupply(), 0);
        assertEq(token.name(), "Kinto Token");
        assertEq(token.symbol(), "K");
        assertEq(token.decimals(), 18);
        assertEq(token.nonces(_user), 0);
        assertEq(token.CLOCK_MODE(), "mode=timestamp");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), upgrader));
    }

    function testMint_WhenDestinationIsEOA() public {
        vm.prank(minter);
        token.mint(_user, 1000);
        assertEq(token.balanceOf(_user), 1500);
    }

    function testMint_WhenDestinationIsContract() public {
        vm.prank(minter);
        token.mint(address(_kintoAppRegistry), 1000);

        assertEq(token.balanceOf(address(_kintoAppRegistry)), 1000);
    }

    function testTransfer_WhenToMiningContract() public {
        vm.prank(admin);
        token.setMiningContract(_user2);

        vm.prank(_user);
        token.transfer(_user2, 500);

        assertEq(token.balanceOf(_user2), 500);
    }

    function testTransfer_WhenFromMiningContract() public {
        vm.prank(admin);
        token.setMiningContract(_user);

        vm.prank(_user);
        token.transfer(_user2, 500);
        assertEq(token.balanceOf(_user2), 500);
    }

    function testTransfer_WhenToTreasury() public {
        vm.prank(_user);
        token.transfer(TREASURY, 500);

        assertEq(token.balanceOf(TREASURY), 500);
    }

    function testTransfer_WhenFromTreasury() public {
        vm.prank(minter);
        token.mint(TREASURY, 1000);

        vm.prank(TREASURY);
        token.transfer(_user2, 500);

        assertEq(token.balanceOf(_user2), 500);
    }

    function testTransfer_RevertWhenToNotAllowedEOA() public {
        vm.prank(_user);
        vm.expectRevert(abi.encodeWithSelector(BridgedKinto.TransferIsNotAllowed.selector, _user, _user2, 500));
        token.transfer(_user2, 500);
    }
}

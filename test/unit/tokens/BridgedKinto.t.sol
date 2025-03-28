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

    function testTransfer_ToEOA() public {
        vm.prank(_user);
        token.transfer(_user2, 500);

        assertEq(token.balanceOf(_user), 0);
        assertEq(token.balanceOf(_user2), 500);
    }

    function testTransfer_BetweenEOAs() public {
        // First transfer to user2
        vm.prank(_user);
        token.transfer(_user2, 300);

        // Then transfer from user2 to user3
        address _user3 = createUser("user3");
        vm.prank(_user2);
        token.transfer(_user3, 100);

        // Verify balances
        assertEq(token.balanceOf(_user), 200);
        assertEq(token.balanceOf(_user2), 200);
        assertEq(token.balanceOf(_user3), 100);
    }

    function testBurnByMinter() public {
        uint256 initialBalance = token.balanceOf(_user);
        uint256 initialSupply = token.totalSupply();
        uint256 burnAmount = 200;

        vm.prank(minter);
        token.burn(_user, burnAmount);

        assertEq(token.balanceOf(_user), initialBalance - burnAmount);
        assertEq(token.totalSupply(), initialSupply - burnAmount);
    }

    function testBurn_TransfersToZeroShouldBeAllowed() public {
        // Our changes to _update allow the contract itself to transfer to address(0) during burn
        // Test with minter role burning tokens from user
        uint256 initialBalance = token.balanceOf(_user);
        uint256 initialSupply = token.totalSupply();
        uint256 burnAmount = 300;

        vm.prank(minter);
        token.burn(_user, burnAmount);

        assertEq(token.balanceOf(_user), initialBalance - burnAmount);
        assertEq(token.totalSupply(), initialSupply - burnAmount);

        // This affirms that our _update function allows transfer to zero address,
        // which is important when calling burn functions
    }
}

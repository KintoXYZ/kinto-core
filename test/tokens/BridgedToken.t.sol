// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {BridgedToken} from "../../src/tokens/BridgedToken.sol";
import {UUPSProxy} from "../helpers/UUPSProxy.sol";
import {UserOp} from "../helpers/UserOp.sol";
import {BridgedTokenHarness} from "../harness/BridgedTokenHarness.sol";
import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";

contract BridgedTokenTest is UserOp {
    address admin;
    address minter;
    address upgrader;
    address alice;

    BridgedToken token;

    function setUp() public {
        admin = createUser("admin");
        minter = createUser("minter");
        upgrader = createUser("upgrader");
        alice = createUser("alice");

        token = BridgedToken(address(new UUPSProxy(address(new BridgedToken()), "")));
        token.initialize("Stablecoin", "DAI", admin, minter, upgrader);
    }

    function testUp() public view {
        assertEq(token.totalSupply(), 0);
        assertEq(token.name(), "Stablecoin");
        assertEq(token.symbol(), "DAI");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), upgrader));
    }

    /* ============ Minter ============ */

    function testMint() public {
        vm.prank(minter);
        token.mint(alice, 1000);

        assertEq(token.balanceOf(alice), 1000);
    }

    function testBurn() public {
        vm.prank(minter);
        token.mint(alice, 1000);

        vm.prank(minter);
        token.burn(alice, 500);

        assertEq(token.balanceOf(alice), 500);
    }

    function testMint_RevertWhen_NotUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, token.MINTER_ROLE())
        );
        vm.prank(alice); // alice does not have MINTER_ROLE
        token.mint(alice, 1000);
    }

    function testBurn_RevertWhen_NotUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, token.MINTER_ROLE())
        );
        vm.prank(alice); // alice does not have MINTER_ROLE
        token.burn(alice, 500);
    }

    /* ============ Proxy ============ */

    function testUpgradeTo() public {
        BridgedTokenHarness newImpl = new BridgedTokenHarness();
        vm.prank(upgrader);
        token.upgradeToAndCall(address(newImpl), bytes(""));

        // new function is working
        assertEq(BridgedTokenHarness(address(token)).answer(), 42);
        // old values kept
        assertEq(token.totalSupply(), 0);
        assertEq(token.name(), "Stablecoin");
        assertEq(token.symbol(), "DAI");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), upgrader));
    }

    function testUpgradeTo_RevertWhen_CallerIsNotUpgrader() public {
        BridgedTokenHarness newImpl = new BridgedTokenHarness();
        // Only the upgrader can upgrade the contract
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, token.UPGRADER_ROLE()
            )
        );
        vm.prank(alice);
        token.upgradeToAndCall(address(newImpl), bytes(""));

        vm.prank(upgrader);
        token.upgradeToAndCall(address(newImpl), bytes(""));

        // new function is working
        assertEq(BridgedTokenHarness(address(token)).answer(), 42);
        // old values kept
        assertEq(token.totalSupply(), 0);
        assertEq(token.name(), "Stablecoin");
        assertEq(token.symbol(), "DAI");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), upgrader));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import {ERC20Bridge} from "../../src/tokens/ERC20Bridge.sol";
import {UUPSProxy} from "../helpers/UUPSProxy.sol";
import {UserOp} from "../helpers/UserOp.sol";
import {ERC20BridgeHarness} from "../harness/ERC20BridgeHarness.sol";
import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";

contract ERC20BridgeTest is UserOp {
    address admin;
    address minter;
    address upgrader;
    address alice;

    ERC20Bridge token;

    function setUp() public {
        admin = createUser("admin");
        minter = createUser("minter");
        upgrader = createUser("upgrader");
        alice = createUser("alice");

        token = ERC20Bridge(address(new UUPSProxy(address(new ERC20Bridge()), "")));
        token.initialize("Stablecoin", "DAI", admin, minter, upgrader);
    }

    function testUp() public {
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
        ERC20BridgeHarness newImpl = new ERC20BridgeHarness();
        vm.prank(upgrader);
        token.upgradeToAndCall(address(newImpl), bytes(""));

        // new function is working
        assertEq(ERC20BridgeHarness(address(token)).answer(), 42);
        // old values kept
        assertEq(token.totalSupply(), 0);
        assertEq(token.name(), "Stablecoin");
        assertEq(token.symbol(), "DAI");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), upgrader));
    }

    function testUpgradeTo_RevertWhen_CallerIsNotUpgrader() public {
        ERC20BridgeHarness newImpl = new ERC20BridgeHarness();
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
        assertEq(ERC20BridgeHarness(address(token)).answer(), 42);
        // old values kept
        assertEq(token.totalSupply(), 0);
        assertEq(token.name(), "Stablecoin");
        assertEq(token.symbol(), "DAI");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), upgrader));
    }
}

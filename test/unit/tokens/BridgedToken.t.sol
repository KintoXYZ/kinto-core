// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";

import {BridgedToken} from "@kinto-core/tokens/bridged/BridgedToken.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {BaseTest} from "@kinto-core-test/helpers/BaseTest.sol";
import {BridgedTokenHarness} from "@kinto-core-test/harness/BridgedTokenHarness.sol";

contract BridgedTokenTest is BaseTest {
    address minter;
    address upgrader;

    BridgedToken token;

    function setUp() public override {
        super.setUp();

        minter = createUser("minter");
        upgrader = createUser("upgrader");

        token = BridgedToken(address(new UUPSProxy(address(new BridgedToken(18)), "")));
        token.initialize("Stablecoin", "DAI", admin0, minter, upgrader);
    }

    function testUp() public view override {
        assertEq(token.totalSupply(), 0);
        assertEq(token.name(), "Stablecoin");
        assertEq(token.symbol(), "DAI");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin0));
        assertTrue(token.hasRole(token.MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), upgrader));
    }

    /* ============ 6 decimal token ============ */
    function testTokenDecimals() public {
        BridgedToken token6 = BridgedToken(address(new UUPSProxy(address(new BridgedToken(6)), "")));
        token6.initialize("USDC", "USDC", admin0, minter, upgrader);
        assertEq(token6.decimals(), 6);
    }

    /* ============ Minter ============ */

    function testMint() public {
        vm.prank(minter);
        token.mint(alice0, 1000);

        assertEq(token.balanceOf(alice0), 1000);
    }

    function testBurn() public {
        vm.prank(minter);
        token.mint(alice0, 1000);

        vm.prank(minter);
        token.burn(alice0, 500);

        assertEq(token.balanceOf(alice0), 500);
    }

    function testMint_RevertWhen_NotUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice0, token.MINTER_ROLE()
            )
        );
        vm.prank(alice0); // alice0 does not have MINTER_ROLE
        token.mint(alice0, 1000);
    }

    function testBurn_RevertWhen_NotUnauthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice0, token.MINTER_ROLE()
            )
        );
        vm.prank(alice0); // alice0 does not have MINTER_ROLE
        token.burn(alice0, 500);
    }

    /* ============ Proxy ============ */

    function testUpgradeTo() public {
        BridgedTokenHarness newImpl = new BridgedTokenHarness(18);
        vm.prank(upgrader);
        token.upgradeToAndCall(address(newImpl), bytes(""));

        // new function is working
        assertEq(BridgedTokenHarness(address(token)).answer(), 42);
        // old values kept
        assertEq(token.totalSupply(), 0);
        assertEq(token.name(), "Stablecoin");
        assertEq(token.symbol(), "DAI");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin0));
        assertTrue(token.hasRole(token.MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), upgrader));
    }

    function testUpgradeTo_RevertWhen_CallerIsNotUpgrader() public {
        BridgedTokenHarness newImpl = new BridgedTokenHarness(18);
        // Only the upgrader can upgrade the contract
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice0, token.UPGRADER_ROLE()
            )
        );
        vm.prank(alice0);
        token.upgradeToAndCall(address(newImpl), bytes(""));

        vm.prank(upgrader);
        token.upgradeToAndCall(address(newImpl), bytes(""));

        // new function is working
        assertEq(BridgedTokenHarness(address(token)).answer(), 42);
        // old values kept
        assertEq(token.totalSupply(), 0);
        assertEq(token.name(), "Stablecoin");
        assertEq(token.symbol(), "DAI");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin0));
        assertTrue(token.hasRole(token.MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), upgrader));
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";

import {BridgedWeth} from "@kinto-core/tokens/BridgedWeth.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {BaseTest} from "@kinto-core-test/helpers/BaseTest.sol";
import {BridgedTokenHarness} from "@kinto-core-test/harness/BridgedTokenHarness.sol";

contract BridgedWethTest is BaseTest {
    address admin;
    address minter;
    address upgrader;
    address alice;

    BridgedWeth token;

    function setUp() public override {
        admin = createUser("admin");
        minter = createUser("minter");
        upgrader = createUser("upgrader");
        alice = createUser("alice");

        token = BridgedWeth(payable(address(new UUPSProxy(address(new BridgedWeth(18)), ""))));
        token.initialize("wrapped eth", "ETH", admin, minter, upgrader);
    }

    function testUp() public view override {
        assertEq(token.totalSupply(), 0);
        assertEq(token.name(), "wrapped eth");
        assertEq(token.symbol(), "ETH");
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), minter));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), upgrader));
    }
}

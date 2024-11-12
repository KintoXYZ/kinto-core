// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/viewers/Viewer.sol";

import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {ERC20Mock} from "@kinto-core-test/helpers/ERC20Mock.sol";
import {BaseTest} from "@kinto-core-test/helpers/BaseTest.sol";

contract ViewerTest is BaseTest {
    Viewer internal viewer;

    ERC20Mock internal token0;
    ERC20Mock internal token1;
    ERC20Mock internal token2;

    function setUp() public override {
        // Deploy Viewer contract
        viewer = new Viewer(address(0), address(0));
        viewer = Viewer(address(new UUPSProxy{salt: 0}(address(viewer), "")));
        viewer.initialize();

        token0 = new ERC20Mock("token0", "TNK0", 18);
        token1 = new ERC20Mock("token1", "TNK1", 18);
        token2 = new ERC20Mock("token2", "TNK2", 18);

        token0.mint(_user, 1);
        token1.mint(_user, 2);
        token2.mint(_user, 3);
    }

    function testInitialize() public {
        viewer = Viewer(address(new UUPSProxy{salt: 0}(address(new Viewer(address(0), address(0))), "")));
        viewer.initialize();

        assertEq(viewer.owner(), address(this));
    }

    /* ============ Viewer tests ============ */

    function testGetBalances() public view {
        // Call getBalances function and check balances
        address[] memory tokens = new address[](3);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(token2);

        uint256[] memory balances = viewer.getBalances(tokens, _user);

        // Assert balances
        assertEq(balances.length, 3);
        assertEq(balances[0], 1);
        assertEq(balances[1], 2);
        assertEq(balances[2], 3);

        balances = viewer.getBalances(tokens, _user2);

        // Assert balances
        assertEq(balances.length, 3);
        assertEq(balances[0], 0);
        assertEq(balances[1], 0);
        assertEq(balances[2], 0);
    }
}

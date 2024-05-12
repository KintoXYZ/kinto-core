// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import { UUPSProxy } from "@kinto-core-test/helpers/UUPSProxy.sol";
import { EngenBadges } from "@kinto-core/tokens/EngenBadges.sol";
import { EngenBadgesHarness } from "@kinto-core-test/harness/EngenBadgesHarness.sol";


import { BaseTest } from "@kinto-core-test/helpers/BaseTest.sol";
import "forge-std/Console.sol";

contract EngenBadgesTest is BaseTest {
    EngenBadges _badges;
    address admin;
    address user;
    string uri = "https://api.example.com/metadata/";

    function setUp() public override {
        admin = createUser("admin");
        user = createUser("user");

        EngenBadges impl = new EngenBadges();
        _badges = EngenBadges(address(new UUPSProxy(address(impl), "")));
        _badges.initialize(uri, admin);
    }

    function testInitialization() public view{
        assertEq(_badges.uri(1), uri);
        assertTrue(_badges.hasRole(_badges.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(_badges.hasRole(_badges.MINTER_ROLE(), admin));
        assertTrue(_badges.hasRole(_badges.UPGRADER_ROLE(), admin));
    }

    function testMintBadges() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        vm.prank(admin);
        _badges.mintBadges(user, ids);

        assertEq(_badges.balanceOf(user, 1), 1);
        assertEq(_badges.balanceOf(user, 2), 1);
    }

    function testMint_RevertWhen_NotMinter() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        vm.expectRevert();
        vm.prank(user);
        _badges.mintBadges(user, ids);
    }

    function testMintBatchRecipients() public {
        address[] memory recipients = new address[](100);
        uint256[][] memory ids = new uint256[][](100);

        for(uint i = 0; i < 100; i++) {
            recipients[i] = address(uint160(0xABCDE + i));
        }

        for(uint i = 0; i < 100; i++) {
            ids[i] = new uint256[](2);
            ids[i][0] = 1;
            ids[i][1] = 2;
        }

        vm.prank(admin);
        _badges.mintBadgesBatch(recipients, ids);

        for(uint i = 0; i < 100; i++) {
            assertEq(_badges.balanceOf(recipients[i], 1), 1);
            assertEq(_badges.balanceOf(recipients[i], 2), 1);
        }
    }

    function testMintBatchRecipients_RevertWhen_101addresses() public {
        address[] memory recipients = new address[](101);
        uint256[][] memory ids = new uint256[][](101);

        for(uint i = 0; i < 101; i++) {
            recipients[i] = address(uint160(0xABCDE + i));
        }

        for(uint i = 0; i < 101; i++) {
            ids[i] = new uint256[](2);
            ids[i][0] = 1;
            ids[i][1] = 2;
        }
        vm.expectRevert("EngenBadges: Cannot mint to more than 100 addresses at a time.");
        vm.prank(admin);
        _badges.mintBadgesBatch(recipients, ids);
    }

    function testUpgradeTo() public {
        EngenBadgesHarness newImpl = new EngenBadgesHarness();
        vm.prank(admin);
        _badges.upgradeTo(address(newImpl));

        // new function working
        assertEq(EngenBadgesHarness(address(_badges)).answer(), 42);
        // old values are kept
        assertEq(_badges.uri(1), uri);
        assertTrue(_badges.hasRole(_badges.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(_badges.hasRole(_badges.MINTER_ROLE(), admin));
        assertTrue(_badges.hasRole(_badges.UPGRADER_ROLE(), admin));
    }

    function testUpgradeTo_RevertWhen_CallerIsNotUpgrader() public {
        EngenBadgesHarness newImpl = new EngenBadgesHarness();
        vm.expectRevert();
        // Attempting to upgrade without proper authorization
        vm.prank(user);
        _badges.upgradeToAndCall(address(newImpl), bytes(""));
    }
}

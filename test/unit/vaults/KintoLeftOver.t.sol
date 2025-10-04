// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ERC20Mock} from "@kinto-core-test/helpers/ERC20Mock.sol";

import {KintoLeftOver} from "@kinto-core/vaults/KintoLeftOver.sol";

contract KintoLeftOverTest is Test {
    // Addresses/constants from KintoLeftOver
    address public constant USDC_ADDR = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant OWNER = 0x2E7111Ef34D39b36EC84C656b947CA746e495Ff6;

    // Test users
    address public alice;
    address public bob;
    address public charlie;
    address public rando;
    address[] public users = new address[](3);
    uint256[] public amounts = new uint256[](3);

    ERC20Mock usdc; // Mocked into USDC_ADDR via vm.etch
    KintoLeftOver leftover;

    function setUp() public {
        // Deploy ERC20Mock, then etch runtime code into canonical USDC address used by the contract
        ERC20Mock impl = new ERC20Mock("USD Coin", "USDC", 6);
        vm.etch(USDC_ADDR, address(impl).code);
        usdc = ERC20Mock(USDC_ADDR);

        // Deploy target contract
        leftover = new KintoLeftOver();

        // Identities
        alice = vm.addr(1);
        bob = vm.addr(2);
        charlie = vm.addr(3);
        rando = vm.addr(444);

        // Fund contract to cover claims
        usdc.mint(address(leftover), 1_000_000_000 * 1e6);

        // Touch balances (not necessary but keeps state explicit)
        usdc.mint(OWNER, 0);
        usdc.mint(alice, 0);
        usdc.mint(bob, 0);
        usdc.mint(charlie, 0);
        usdc.mint(rando, 0);
    }

    /* ============ Deployment ============ */

    function testDeploymentConfig() public view {
        // Owner is the constant OWNER
        assertEq(leftover.owner(), OWNER);
        // USDC address should be the canonical one
        assertEq(address(leftover.USDC()), USDC_ADDR);
    }

    /* ============ acceptAndClaim ============ */

    function testAcceptAndClaim_HappyPath() public {
        // Owner seeds Alice with 123,456 USDC (6dp)
        vm.prank(OWNER);
        leftover.updateUserInfo(alice, KintoLeftOver.UserInfo({amount: 123_456 * 1e6, claimed: false}));

        uint256 before = usdc.balanceOf(alice);
        vm.prank(alice);
        leftover.acceptAndClaim();

        // Received funds + flag flipped
        assertEq(usdc.balanceOf(alice) - before, 123_456 * 1e6);
        (uint256 amt, bool claimed) = leftover.userInfos(alice);
        assertEq(amt, 123_456 * 1e6);
        assertTrue(claimed);
    }

    function testAcceptAndClaim_RevertAlreadyClaimed() public {
        vm.startPrank(OWNER);
        leftover.updateUserInfo(alice, KintoLeftOver.UserInfo({amount: 1 * 1e6, claimed: false}));
        vm.stopPrank();

        vm.prank(alice);
        leftover.acceptAndClaim();

        vm.prank(alice);
        vm.expectRevert(bytes("Already claimed"));
        leftover.acceptAndClaim();
    }

    function testAcceptAndClaim_RevertNothingToClaim() public {
        // rando has no allocation
        vm.prank(rando);
        vm.expectRevert(bytes("Nothing to claim"));
        leftover.acceptAndClaim();
    }

    /* ============ Admin: updateUserInfo ============ */

    function testUpdateUserInfo_OnlyOwner() public {
        KintoLeftOver.UserInfo memory info = KintoLeftOver.UserInfo({amount: 10_000 * 1e6, claimed: false});

        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        leftover.updateUserInfo(rando, info);
    }

    function testUpdateUserInfo_RejectsClaimedFlag() public {
        vm.stopPrank();
        vm.startPrank(OWNER);
        leftover.updateUserInfo(alice, KintoLeftOver.UserInfo({amount: 1 * 1e6, claimed: false}));
        vm.stopPrank();

        vm.prank(alice);
        leftover.acceptAndClaim();

        KintoLeftOver.UserInfo memory bad = KintoLeftOver.UserInfo({amount: 90_000 * 1e6, claimed: false});

        vm.prank(OWNER);
        vm.expectRevert(bytes("User immutable"));
        leftover.updateUserInfo(alice, bad);
    }

    function testUpdateUserInfo_SetsThenClaim() public {
        vm.prank(OWNER);
        leftover.updateUserInfo(bob, KintoLeftOver.UserInfo({amount: 777_777 * 1e6, claimed: false}));

        // Verify set
        (uint256 amt, bool claimed) = leftover.userInfos(bob);
        assertEq(amt, 777_777 * 1e6);
        assertFalse(claimed);

        // Claim works
        uint256 before = usdc.balanceOf(bob);
        vm.prank(bob);
        leftover.acceptAndClaim();
        assertEq(usdc.balanceOf(bob) - before, 777_777 * 1e6);
        (, claimed) = leftover.userInfos(bob);
        assertTrue(claimed);
    }

    /* ============ Admin: setUsersInfo ============ */

    function testSetUsersInfo_OnlyOwner() public {
        users[0] = alice;
        amounts[0] = 5_000 * 1e6;

        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        leftover.setUsersInfo(users, amounts);
    }

    function testSetUsersInfo_LengthMismatch() public {
        address[] memory users2 = new address[](1);
        users2[0] = alice;

        uint256[] memory amounts2 = new uint256[](2);
        amounts2[0] = 1 * 1e6;
        amounts2[1] = 1 * 1e6;

        vm.prank(OWNER);
        vm.expectRevert(bytes("Invalid params"));
        leftover.setUsersInfo(users2, amounts2);
    }

    function testSetUsersInfo_UserAlreadyClaimedReverts() public {
        // Seed & claim for Alice
        vm.prank(OWNER);
        leftover.updateUserInfo(alice, KintoLeftOver.UserInfo({amount: 10 * 1e6, claimed: false}));
        vm.prank(alice);
        leftover.acceptAndClaim();

        // Now try to set Alice again via batch; should revert on "User already claimed"
        users[0] = alice; // already claimed
        users[1] = bob;

        amounts[0] = 1 * 1e6;
        amounts[1] = 2 * 1e6;

        vm.prank(OWNER);
        vm.expectRevert(bytes("User already claimed"));
        leftover.setUsersInfo(users, amounts);
    }

    function testSetUsersInfo_NormalMultiUserThenClaims() public {
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;

        amounts[0] = 50_000 * 1e6;
        amounts[1] = 75_500 * 1e6;
        amounts[2] = 90 * 1e6;

        vm.prank(OWNER);
        leftover.setUsersInfo(users, amounts);

        // Verify stored
        (uint256 aAmt, bool aClaimed) = leftover.userInfos(alice);
        (uint256 bAmt, bool bClaimed) = leftover.userInfos(bob);
        (uint256 cAmt, bool cClaimed) = leftover.userInfos(charlie);
        assertEq(aAmt, 50_000 * 1e6);
        assertFalse(aClaimed);
        assertEq(bAmt, 75_500 * 1e6);
        assertFalse(bClaimed);
        assertEq(cAmt, 90 * 1e6);
        assertFalse(cClaimed);

        // Alice claims
        uint256 aBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        leftover.acceptAndClaim();
        assertEq(usdc.balanceOf(alice) - aBefore, 50_000 * 1e6);

        // Bob claims
        uint256 bBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        leftover.acceptAndClaim();
        assertEq(usdc.balanceOf(bob) - bBefore, 75_500 * 1e6);

        // Charlie claims
        uint256 cBefore = usdc.balanceOf(charlie);
        vm.prank(charlie);
        leftover.acceptAndClaim();
        assertEq(usdc.balanceOf(charlie) - cBefore, 90 * 1e6);
    }

    /* ============ Admin: emergencyRecover ============ */

    function testEmergencyRecover_OnlyOwner() public {
        vm.prank(rando);
        vm.expectRevert("Ownable: caller is not the owner");
        leftover.emergencyRecover();
    }

    function testEmergencyRecover_PullsAllFundsToOwner() public {
        // Top up contract a distinct amount, then recover
        uint256 extra = 321_000 * 1e6;
        usdc.mint(address(leftover), extra);

        uint256 ownerBefore = usdc.balanceOf(OWNER);
        uint256 contractBal = usdc.balanceOf(address(leftover));

        vm.prank(OWNER);
        leftover.emergencyRecover();

        assertEq(usdc.balanceOf(OWNER), ownerBefore + contractBal);
        assertEq(usdc.balanceOf(address(leftover)), 0);
    }
}

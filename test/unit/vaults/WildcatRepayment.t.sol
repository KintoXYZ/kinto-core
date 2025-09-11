// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {ERC20Mock} from "@kinto-core-test/helpers/ERC20Mock.sol";

import {WildcatRepayment} from "@kinto-core/vaults/WildcatRepayment.sol";

contract WildcatRepaymentTest is Test {
    // Constants from the contract
    address public constant USDC_ADDR = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant OWNER = 0x2E7111Ef34D39b36EC84C656b947CA746e495Ff6;

    // One of the preset users in constructor
    address public constant LENDER_A = 0x5b1b1Ef66214fe163B602FC5B81903906A786211; // firstClaim: 250,000e6 ; second: 130,000e6
    address public constant LENDER_B = 0x4086f688855dcAe061e7f68fc181566FFfa856eA; // firstClaim: 100,396.5e6 ; second: 52,206.18e6
    address public randomUser;

    ERC20Mock usdc; // at the USDC_ADDR (via etch)
    WildcatRepayment repay;

    function setUp() public {
        // 1) Deploy a mock ERC20 and etch its runtime code into the canonical USDC address used by the contract
        ERC20Mock impl = new ERC20Mock("USD Coin", "USDC", 6);
        vm.etch(USDC_ADDR, address(impl).code);
        usdc = ERC20Mock(USDC_ADDR);

        // 2) Deploy the repayment contract
        repay = new WildcatRepayment();

        // fund contract with plenty of USDC for claims
        usdc.mint(address(repay), 1_000_000_000 * 1e6);

        // Allocate some USDC to users (not strictly needed, but handy)
        randomUser = vm.addr(999);
        usdc.mint(OWNER, 0); // ensure storage slot for OWNER exists in the mock token
        usdc.mint(LENDER_A, 0);
        usdc.mint(LENDER_B, 0);
        usdc.mint(randomUser, 0);
    }

    /* ============ Deployment ============ */

    function testDeploymentConfig() public {
        // Owner should be the constant OWNER
        assertEq(repay.owner(), OWNER);
        // secondPeriodOpen default false
        assertEq(repay.secondPeriodOpen(), false);
        // USDC address baked in and used
        assertEq(address(repay.USDC()), USDC_ADDR);
    }

    /* ============ Claim First ============ */

    function testAcceptAndClaimFirst_HappyPath() public {
        // Read assigned amount from the contract mapping
        (uint256 first,, bool claimedFirst,) = repay.userInfos(LENDER_A);
        assertEq(first, 250_000 * 1e6);
        assertFalse(claimedFirst);

        uint256 balBefore = usdc.balanceOf(LENDER_A);
        vm.prank(LENDER_A);
        repay.acceptAndClaimFirst();

        // User received funds
        assertEq(usdc.balanceOf(LENDER_A), balBefore + first);
        // Claimed flag flipped
        (,, claimedFirst,) = repay.userInfos(LENDER_A);
        assertTrue(claimedFirst);
    }

    function testAcceptAndClaimFirst_RevertAlreadyClaimed() public {
        vm.startPrank(LENDER_A);
        repay.acceptAndClaimFirst();
        vm.expectRevert(bytes("Already claimed"));
        repay.acceptAndClaimFirst();
        vm.stopPrank();
    }

    function testAcceptAndClaimFirst_RevertNothingToClaim() public {
        // random user has no allocation
        vm.prank(randomUser);
        vm.expectRevert(bytes("Nothing to claim"));
        repay.acceptAndClaimFirst();
    }

    /* ============ Claim Second ============ */

    function testAcceptAndClaimSecond_RevertNotOpen() public {
        vm.prank(LENDER_A);
        vm.expectRevert(bytes("Second period not open"));
        repay.acceptAndClaimSecond();
    }

    function testAcceptAndClaimSecond_HappyPath() public {
        // Start by owner
        vm.prank(OWNER);
        repay.startSecondPeriod();
        assertTrue(repay.secondPeriodOpen());

        (, uint256 second,, bool claimedSecond) = repay.userInfos(LENDER_A);
        assertEq(second, 130_000 * 1e6);
        assertFalse(claimedSecond);

        uint256 balBefore = usdc.balanceOf(LENDER_A);
        vm.prank(LENDER_A);
        repay.acceptAndClaimSecond();

        assertEq(usdc.balanceOf(LENDER_A), balBefore + second);
        (,,, claimedSecond) = repay.userInfos(LENDER_A);
        assertTrue(claimedSecond);
    }

    function testAcceptAndClaimSecond_RevertAlreadyClaimed() public {
        vm.prank(OWNER);
        repay.startSecondPeriod();

        vm.startPrank(LENDER_A);
        repay.acceptAndClaimSecond();
        vm.expectRevert(bytes("Already claimed"));
        repay.acceptAndClaimSecond();
        vm.stopPrank();
    }

    function testAcceptAndClaimSecond_RevertNothingToClaim() public {
        vm.prank(OWNER);
        repay.startSecondPeriod();

        vm.prank(randomUser);
        vm.expectRevert(bytes("Nothing to claim"));
        repay.acceptAndClaimSecond();
    }

    /* ============ Admin: startSecondPeriod ============ */

    function testStartSecondPeriod_OnlyOwner() public {
        vm.prank(randomUser);
        vm.expectRevert("Ownable: caller is not the owner");
        repay.startSecondPeriod();

        vm.prank(OWNER);
        repay.startSecondPeriod();
        assertTrue(repay.secondPeriodOpen());
    }

    /* ============ Admin: updateUserInfo ============ */

    function testUpdateUserInfo_OnlyOwner() public {
        WildcatRepayment.UserInfo memory info = WildcatRepayment.UserInfo({
            firstClaim: 123 * 1e6,
            secondClaim: 456 * 1e6,
            claimedFirst: false,
            claimedSecond: false
        });

        vm.prank(randomUser);
        vm.expectRevert("Ownable: caller is not the owner");
        repay.updateUserInfo(randomUser, info);
    }

    function testUpdateUserInfo_RejectsClaimedFlags() public {
        WildcatRepayment.UserInfo memory bad =
            WildcatRepayment.UserInfo({firstClaim: 1, secondClaim: 1, claimedFirst: true, claimedSecond: false});

        vm.prank(OWNER);
        vm.expectRevert(bytes("User immutable"));
        repay.updateUserInfo(randomUser, bad);

        bad = WildcatRepayment.UserInfo({firstClaim: 1, secondClaim: 1, claimedFirst: false, claimedSecond: true});

        vm.prank(OWNER);
        vm.expectRevert(bytes("User immutable"));
        repay.updateUserInfo(randomUser, bad);
    }

    function testUpdateUserInfo_SetsValues_ThenClaimsWork() public {
        WildcatRepayment.UserInfo memory info = WildcatRepayment.UserInfo({
            firstClaim: 1_234_567 * 1e6,
            secondClaim: 765_432 * 1e6,
            claimedFirst: false,
            claimedSecond: false
        });

        vm.prank(OWNER);
        repay.updateUserInfo(randomUser, info);

        // Check stored
        (uint256 f, uint256 s, bool c1, bool c2) = repay.userInfos(randomUser);
        assertEq(f, 1_234_567 * 1e6);
        assertEq(s, 765_432 * 1e6);
        assertFalse(c1);
        assertFalse(c2);

        // First claim
        uint256 before = usdc.balanceOf(randomUser);
        vm.prank(randomUser);
        repay.acceptAndClaimFirst();
        assertEq(usdc.balanceOf(randomUser) - before, f);

        // Open second period, then claim
        vm.prank(OWNER);
        repay.startSecondPeriod();

        before = usdc.balanceOf(randomUser);
        vm.prank(randomUser);
        repay.acceptAndClaimSecond();
        assertEq(usdc.balanceOf(randomUser) - before, s);
    }

    /* ============ Admin: emergencyRecover ============ */

    function testEmergencyRecover_OnlyOwner() public {
        vm.prank(randomUser);
        vm.expectRevert("Ownable: caller is not the owner");
        repay.emergencyRecover();
    }

    function testEmergencyRecover_PullsAllFundsToOwner() public {
        // Top up contract, then recover
        uint256 extra = 777_000 * 1e6;
        usdc.mint(address(repay), extra);

        uint256 ownerBefore = usdc.balanceOf(OWNER);
        uint256 contractBal = usdc.balanceOf(address(repay));

        vm.prank(OWNER);
        repay.emergencyRecover();

        assertEq(usdc.balanceOf(OWNER), ownerBefore + contractBal);
        assertEq(usdc.balanceOf(address(repay)), 0);
    }
}

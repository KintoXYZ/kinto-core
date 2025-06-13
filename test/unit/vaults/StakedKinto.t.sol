// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@kinto-core-test/helpers/ERC20Mock.sol";
import {StakedKinto} from "@kinto-core/vaults/StakedKinto.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {
    IERC20Upgradeable,
    IERC20MetadataUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";

contract StakedKintoUpgraded is StakedKinto {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor() StakedKinto() {}
}

contract StakedKintoTest is SharedSetup {
    StakedKinto public vault;
    ERC20Mock public kToken; // Staking token
    ERC20Mock public usdc; // Reward token

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18; // 1 million K tokens
    uint256 public constant REWARD_AMOUNT = 100_000 * 1e6; // 100,000 USDC
    uint256 public constant REWARD_RATE = 3; // 20% APY from price / 5
    uint256 public constant MAX_CAPACITY = 500_000 * 1e18; // 500,000 K tokens max capacity

    uint256 public startTime;
    uint256 public endTime;

    function setUp() public override {
        super.setUp();

        // Deploy mock tokens
        kToken = new ERC20Mock("Kinto Token", "K", 18);
        usdc = new ERC20Mock("USD Coin", "USDC", 6);

        // Set timestamps for the vault
        startTime = block.timestamp;
        endTime = startTime + 365 days;

        // Deploy vault
        vault = new StakedKinto();
        vm.startPrank(admin);
        vault = StakedKinto(address(new UUPSProxy{salt: 0}(address(vault), "")));
        vault.initialize(
            IERC20MetadataUpgradeable(address(kToken)),
            ERC20Upgradeable(address(usdc)),
            REWARD_RATE,
            endTime,
            "Staked Kinto",
            "stK",
            MAX_CAPACITY
        );

        vm.stopPrank();
        // Transfer some tokens to test users
        kToken.mint(alice, MAX_CAPACITY);
        kToken.mint(bob, MAX_CAPACITY);
        kToken.mint(charlie, MAX_CAPACITY);
        usdc.mint(alice, REWARD_AMOUNT * 100);

        // Transfer reward tokens to the vault
        vm.startPrank(alice);
        usdc.transfer(address(vault), REWARD_AMOUNT * 100);
        vm.stopPrank();

        // Approve vault to spend tokens
        vm.startPrank(alice);
        kToken.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        kToken.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(charlie);
        kToken.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    /* ============ ERC4626 Interface Tests ============ */

    function testAsset() public view {
        assertEq(address(vault.asset()), address(kToken));
    }

    function testTotalAssets() public {
        assertEq(vault.totalAssets(), 0);

        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);

        assertEq(vault.totalAssets(), 1000 * 1e18);
    }

    function testConvertToShares() public {
        // With empty vault, 1:1 conversion
        assertEq(vault.convertToShares(1000 * 1e18), 1000 * 1e18);

        // Deposit some assets
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);

        // Still 1:1 initially
        assertEq(vault.convertToShares(1000 * 1e18), 1000 * 1e18);
    }

    function testConvertToAssets() public {
        // With empty vault, 1:1 conversion
        assertEq(vault.convertToAssets(1000 * 1e18), 1000 * 1e18);

        // Deposit some assets
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);

        // Still 1:1 initially
        assertEq(vault.convertToAssets(1000 * 1e18), 1000 * 1e18);
    }

    function testMaxDeposit() public {
        // Max deposit should be the max capacity initially
        assertEq(vault.maxDeposit(alice), MAX_CAPACITY);

        // Deposit half the capacity
        vm.prank(alice);
        vault.deposit(MAX_CAPACITY / 2, alice);

        // Max deposit should be the remaining capacity
        assertEq(vault.maxDeposit(alice), MAX_CAPACITY / 2);

        // Deposit the rest
        vm.prank(bob);
        vault.deposit(MAX_CAPACITY / 2, bob);

        // Max deposit should be 0 now
        assertEq(vault.maxDeposit(charlie), 0);
    }

    function testMaxMint() public {
        // Make sure we're using the same token instance as in setUp
        vm.startPrank(alice);
        kToken.approve(address(vault), type(uint256).max);

        // Max mint should be equivalent to max deposit initially
        assertEq(vault.maxMint(alice), vault.convertToShares(MAX_CAPACITY));

        // Mint half the capacity
        vault.mint(vault.convertToShares(MAX_CAPACITY / 2), alice);
        vm.stopPrank();

        // Max mint should be the remaining capacity in shares
        assertEq(vault.maxMint(alice), vault.convertToShares(MAX_CAPACITY / 2));
    }

    function testMaxWithdraw() public {
        // Max withdraw should be 0 initially
        assertEq(vault.maxWithdraw(alice), 0);

        // Deposit some assets
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);

        // Max withdraw should be 0 before end date
        assertEq(vault.maxWithdraw(alice), 0);

        // Advance time to after end date
        vm.warp(endTime + 1);

        // Check the actual value before asserting
        uint256 actualMaxWithdraw = vault.maxWithdraw(alice);

        // Use the actual value or fix the contract implementation
        assertEq(actualMaxWithdraw, 1000 * 1e18);
    }

    function testMaxRedeem() public {
        // Max redeem should be 0 initially
        assertEq(vault.maxRedeem(alice), 0);

        // Deposit some assets
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);

        // Max redeem should be 0 before end date
        assertEq(vault.maxRedeem(alice), 0);

        // Advance time to after end date
        vm.warp(endTime + 1);

        // Max redeem should be the deposited shares
        assertEq(vault.maxRedeem(alice), 1000 * 1e18);
    }

    function testPreviewDeposit() public view {
        // Preview deposit should match convertToShares
        assertEq(vault.previewDeposit(1000 * 1e18), vault.convertToShares(1000 * 1e18));
    }

    function testPreviewMint() public view {
        // Preview mint should match convertToAssets for the inverse operation
        assertEq(vault.previewMint(1000 * 1e18), vault.convertToAssets(1000 * 1e18));
    }

    function testPreviewWithdraw() public view {
        // Preview withdraw should match convertToShares for the inverse operation
        assertEq(vault.previewWithdraw(1000 * 1e18), vault.convertToShares(1000 * 1e18));
    }

    function testPreviewRedeem() public view {
        // Preview redeem should match convertToAssets
        assertEq(vault.previewRedeem(1000 * 1e18), vault.convertToAssets(1000 * 1e18));
    }

    /* ============ Deposit/Mint Tests ============ */

    function testDeposit() public {
        uint256 depositAmount = 1000 * 1e18;

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        assertEq(shares, depositAmount); // 1:1 conversion initially
        assertEq(vault.balanceOf(alice), depositAmount);
        assertEq(vault.totalAssets(), depositAmount);

        // Check user stake info
        (uint256 amount, uint256 weightedTimestamp,) = vault.getUserStakeInfo(alice, vault.currentPeriodId());
        assertEq(amount, depositAmount);
        assertEq(weightedTimestamp, block.timestamp);
    }

    function testMultipleDeposits() public {
        // First deposit
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);

        uint256 firstTimestamp = block.timestamp;

        // Advance time
        vm.warp(block.timestamp + 10 days);

        // Second deposit
        vm.prank(alice);
        vault.deposit(2000 * 1e18, alice);

        // Check user stake info - weighted timestamp should be calculated correctly
        (uint256 amount, uint256 weightedTimestamp,) = vault.getUserStakeInfo(alice, vault.currentPeriodId());
        assertEq(amount, 3000 * 1e18);

        // Calculate expected weighted timestamp: (1000 * firstTimestamp + 2000 * (firstTimestamp + 10 days)) / 3000
        uint256 expectedWeightedTimestamp = (1000 * firstTimestamp + 2000 * (firstTimestamp + 10 days)) / 3000;
        assertEq(weightedTimestamp, expectedWeightedTimestamp);
    }

    function testMint() public {
        uint256 mintAmount = 1000 * 1e18;

        vm.prank(alice);
        uint256 assets = vault.mint(mintAmount, alice);

        assertEq(assets, mintAmount); // 1:1 conversion initially
        assertEq(vault.balanceOf(alice), mintAmount);
        assertEq(vault.totalAssets(), mintAmount);
    }

    function testDepositWhenCapacityReached() public {
        // Deposit up to capacity
        vm.prank(alice);
        vault.deposit(MAX_CAPACITY, alice);

        // Try to deposit more
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("MaxCapacityReached()"));
        vault.deposit(1000 * 1e18, bob);
    }

    function testDepositAfterEndDate() public {
        // Advance time to after end date
        vm.warp(endTime + 1);

        // Try to deposit
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("StakingPeriodEnded()"));
        vault.deposit(1000 * 1e18, alice);
    }

    /* ============ Withdraw/Redeem Tests ============ */

    function testWithdrawBeforeEndDate() public {
        // Deposit
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);

        // Try to withdraw before end date
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("CannotWithdrawBeforeEndDate()"));
        vault.withdraw(1000 * 1e18, alice, alice);
    }

    function testWithdrawAfterEndDate() public {
        // Deposit
        uint256 aliceBalance = kToken.balanceOf(alice);
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);

        // Advance time to after end date
        vm.warp(endTime + 1);

        // Start a new period so currentPid becomes 1
        vm.prank(admin);
        vault.startNewPeriod(block.timestamp + 30 days, 10, 1_000_000 ether, address(usdc));

        // Withdraw
        vm.prank(alice);
        uint256 assets = vault.withdraw(1000 * 1e18, alice, alice);

        assertEq(assets, 1000 * 1e18);
        assertEq(kToken.balanceOf(alice), aliceBalance); // Original balance restored
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalAssets(), 0);

        // Check rewards
        assertGt(usdc.balanceOf(alice), 0); // Should have received some rewards
    }

    function testRedeemBeforeEndDate() public {
        // Deposit
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);

        // Try to redeem before end date
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("CannotWithdrawBeforeEndDate()"));
        vault.redeem(1000 * 1e18, alice, alice);
    }

    function testRedeemAfterEndDate() public {
        // Deposit
        uint256 aliceBalance = kToken.balanceOf(alice);
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);

        // Advance time to after end date
        vm.warp(endTime + 1);

        // Start a new period so currentPid becomes 1
        vm.prank(admin);
        vault.startNewPeriod(block.timestamp + 30 days, 10, 1_000_000 ether, address(usdc));

        // Redeem
        vm.prank(alice);
        uint256 assets = vault.redeem(1000 * 1e18, alice, alice);

        assertEq(assets, 1000 * 1e18);
        assertEq(kToken.balanceOf(alice), aliceBalance); // Original balance restored
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalAssets(), 0);

        // Check rewards
        assertGt(usdc.balanceOf(alice), 0); // Should have received some rewards
    }

    /* ============ ICO Stake Token Tests ============ */

    function testIcoTokensActionWhenWithdrawing() public {
        // Deposit
        uint256 bobBalance = kToken.balanceOf(bob);
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);

        // Advance time to after end date
        vm.warp(endTime + 1);

        // Start a new period so currentPid becomes 1
        vm.prank(admin);
        vault.startNewPeriod(block.timestamp + 30 days, 10, 1_000_000 ether, address(usdc));

        // Transfer some to BOb
        vm.prank(alice);
        vault.transfer(bob, 10 * 1e18);

        // Withdraw
        vm.prank(bob);
        vault.icoTokensAction(10 * 1e18, true, 1);

        // Check balances
        assertEq(vault.balanceOf(alice), 990 * 1e18);
        assertEq(vault.totalAssets(), 990 * 1e18);
        assertEq(kToken.balanceOf(bob), bobBalance + 10 * 1e18);
        assertEq(vault.balanceOf(bob), 0);

        // Check rewards
        assertEq(usdc.balanceOf(bob), 25 * 1e5); // Should have received some rewards
    }

    function testIcoTokensActionWhenDepositing() public {
        // Deposit
        uint256 bobBalance = kToken.balanceOf(bob);
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);

        // Advance time to after end date
        vm.warp(endTime + 1);

        // Start a new period so currentPid becomes 1
        vm.prank(admin);
        vault.startNewPeriod(block.timestamp + 30 days, 10, 1_000_000 ether, address(usdc));

        // Transfer some to BOb
        vm.prank(alice);
        vault.transfer(bob, 10 * 1e18);

        // Withdraw
        vm.prank(bob);
        vault.icoTokensAction(10 * 1e18, false, 2);

        // Check balances
        assertEq(vault.balanceOf(alice), 990 * 1e18);
        assertEq(vault.totalAssets(), 1000 * 1e18);
        assertEq(kToken.balanceOf(bob), bobBalance);
        assertEq(vault.balanceOf(bob), 10 * 1e18);

        // Check user stake info
        (uint256 amount, uint256 weightedTimestamp,) = vault.getUserStakeInfo(bob, vault.currentPeriodId());
        assertGt(amount, 10 * 1e18); // includes bonus
        assertEq(weightedTimestamp, block.timestamp);

        // Check rewards
        assertEq(usdc.balanceOf(bob), 50 * 1e5); // Should have received some rewards
    }

    function testIcoTokensRevertWhenWithdrawingTooMuch() public {
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);

        // Advance time to after end date
        vm.warp(endTime + 1);

        // Start a new period so currentPid becomes 1
        vm.prank(admin);
        vault.startNewPeriod(block.timestamp + 30 days, 10, 1_000_000 ether, address(usdc));

        // Transfer some to BOb
        vm.prank(alice);
        vault.transfer(bob, 10 * 1e18);

        // Withdraw
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("DepositTooSmall()"));
        vault.icoTokensAction(11 * 1e18, true, 1);
    }

    /* ============ Rewards Tests ============ */

    function testCalculateRewards() public {
        // Deposit
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);

        vm.warp(block.timestamp + 365 days);

        // Calculate expected rewards: amount * rate * duration * 2 / (365 days)
        uint256 expectedRewards = (1000 * 1e18 * REWARD_RATE * 365 days * 2) / (365 days * (10 ** 12));
        assertApproxEqAbs(vault.calculateRewards(alice, 0), expectedRewards, 10); // Allow small rounding difference
    }

    function testRewardsDistribution() public {
        // Deposit from multiple users
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);

        vm.prank(bob);
        vault.deposit(2000 * 1e18, bob);

        // Advance time to after end date
        vm.warp(endTime + 1);

        // Withdraw and check rewards
        vm.prank(alice);
        vault.withdraw(1000 * 1e18, alice, alice);

        vm.prank(bob);
        vault.withdraw(2000 * 1e18, bob, bob);

        // Bob should have approximately twice the rewards of Alice
        assertApproxEqRel(usdc.balanceOf(bob), usdc.balanceOf(alice) * 2, 0.01e18); // 1% tolerance
    }

    /* ============ Admin Functions Tests ============ */

    function testSetMaxCapacity() public {
        uint256 newCapacity = 1_000_000 * 1e18;

        vm.prank(admin);
        vault.setMaxCapacity(newCapacity);

        (,,, uint256 maxCapacity, address rewardToken) = vault.getPeriodInfo(0);
        assertEq(maxCapacity, newCapacity);
        assertEq(vault.maxDeposit(alice), newCapacity);
        assertEq(rewardToken, address(usdc));
    }

    function testSetMaxCapacityUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert(); // Should revert with Ownable error
        vault.setMaxCapacity(1_000_000 * 1e18);
    }

    function testUpgradeTo_RevertWhen_CallerIsNotOwner(address someone) public {
        vm.assume(someone != _owner);
        StakedKintoUpgraded _implementationV2 = new StakedKintoUpgraded();
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(someone);
        vault.upgradeTo(address(_implementationV2));
    }

    function testUpgradeTo() public {
        StakedKinto _implementationV2 = new StakedKintoUpgraded();
        vm.prank(vault.owner());
        vault.upgradeTo(address(_implementationV2));
        assertEq(StakedKintoUpgraded(address(vault)).newFunction(), 1);
    }

    /* ============ Deposit with bonus Tests ============ */

    /// No bonus when untilPeriodId == currentPeriodId
    function testDepositWithBonusNoBonus() public {
        uint256 amount = 1_000 ether;
        uint256 currentPid = vault.currentPeriodId();
        _depositWithBonus(alice, amount, currentPid);

        (uint256 aAmt,,) = vault.getUserStakeInfo(alice, vault.currentPeriodId());
        assertEq(aAmt, amount, "Unexpected bonus applied");
        assertEq(vault.balanceOf(alice), amount, "Shares mismatch");
    }

    /// 4 % bonus per future period
    function testDepositWithBonusAddsFourPercent() public {
        uint256 amount = 2_000 ether;
        uint256 untilPid = vault.currentPeriodId() + 1; // lock one extra period
        uint256 shares = _depositWithBonus(alice, amount, untilPid);

        uint256 expected = (amount * 104) / 100; // +4 %
        assertEq(shares, expected, "Returned shares wrong");

        (uint256 aAmt,,) = vault.getUserStakeInfo(alice, vault.currentPeriodId());
        assertEq(aAmt, expected, "Stake amount without bonus");
        assertEq(vault.balanceOf(alice), amount, "Vault balance wrong");

        // untilPeriodId stored correctly
        (,, uint256 pending) = vault.getUserStakeInfo(alice, vault.currentPeriodId());
        assertEq(pending, vault.calculateRewards(alice, vault.currentPeriodId()), "Pending mismatch");
    }

    function testDepositWithBonusTwoPeriodsAddsNinePercent() public {
        uint256 amount = 3_000 ether;
        uint256 untilPid = vault.currentPeriodId() + 2; // diff = 2 (10 %)
        uint256 shares = _depositWithBonus(bob, amount, untilPid);

        uint256 expected = (amount * 109) / 100;
        assertEq(shares, expected, "Shares wrong for diff=2");
        (uint256 bAmt,,) = vault.getUserStakeInfo(bob, vault.currentPeriodId());
        assertEq(bAmt, expected, "Stake amt wrong for diff=2");
    }

    /// untilPeriodId < currentPeriodId should revert with arithmetic error (underflow)
    function testDepositWithBonusInvalidUntilPeriod() public {
        // Start a new period so currentPid becomes 1
        uint256 newEnd = block.timestamp + 30 days;
        vm.prank(admin);
        vault.startNewPeriod(newEnd, 10, 1_000_000 ether, address(usdc));

        vm.prank(alice);
        vm.expectRevert();
        vault.depositWithBonus(100 ether, alice, 0);
    }

    /* ============ afterTokenTransfer() Tests ============ */

    /// @dev Stake should follow `transfer` and merge correctly when receiver already has a stake.
    function testTransferMovesStakeData() public {
        uint256 amt = 1_000 ether;

        // alice & bob both deposit
        _deposit(alice, amt); // ts = t0
        vm.warp(block.timestamp + 10);
        _deposit(bob, amt / 2); // ts = t0 + 10

        // Alice transfers her shares to Bob
        vm.prank(alice);
        vault.transfer(bob, amt);

        // alice position should be gone
        (uint256 aAmt,,) = vault.getUserStakeInfo(alice, vault.currentPeriodId());
        assertEq(aAmt, 0, "Alice stake not cleared");

        // bob position should now be amt + amt/2 with correct weighted timestamp
        (uint256 bAmt, uint256 wts,) = vault.getUserStakeInfo(bob, vault.currentPeriodId());
        assertEq(bAmt, (3 * amt) / 2, "Bob merged amount incorrect");
        // weightedTimestamp = (amt*t0 + (amt/2)*(t0+10)) / (1.5*amt) = t0 + 3.33…
        uint256 expectedWts = (block.timestamp - 10) + 3; // block.timestamp is t0+10 here
        assertApproxEqAbs(wts, expectedWts, 1, "Weighted timestamp skewed");
    }

    /// @dev transferFrom path should also move stake info (covers ERC20 permit / allowances).
    function testTransferFromMovesStakeData() public {
        uint256 amt = 500 ether;
        _deposit(alice, amt);

        // Grant allowance to bob and perform transferFrom
        vm.prank(alice);
        vault.approve(bob, amt);

        vm.prank(bob);
        vault.transferFrom(alice, bob, amt);

        (uint256 aAmt,,) = vault.getUserStakeInfo(alice, vault.currentPeriodId());
        assertEq(aAmt, 0, "Stake stayed with Alice after transferFrom");

        (uint256 bAmt,,) = vault.getUserStakeInfo(bob, vault.currentPeriodId());
        assertEq(bAmt, amt, "Stake did not reach Bob via transferFrom");
    }

    /// @dev Self‑transfer should be a no‑op and must not delete stake info.
    function testSelfTransferNoOp() public {
        uint256 amt = 750 ether;
        _deposit(alice, amt);

        vm.prank(alice);
        vault.transfer(alice, amt);

        (uint256 aAmt,,) = vault.getUserStakeInfo(alice, vault.currentPeriodId());
        assertEq(aAmt, amt, "Selftransfer corrupted stake info");
    }

    /// @dev If sender already claimed in a period and receiver has not, transfer must revert.
    function testTransferAfterClaimReverts() public {
        uint256 amt = 1_000 ether;
        _deposit(alice, amt);
        _deposit(bob, amt);

        // Warp past period end so Alice can withdraw (and auto‑claim)
        vm.warp(endTime + 1);
        // Start a new period so currentPid becomes 1
        vm.prank(admin);
        vault.startNewPeriod(block.timestamp + 30 days, 10, 1_000_000 ether, address(usdc));

        vm.prank(alice);
        vault.withdraw(amt / 2, alice, alice); // partial withdraw triggers _handleRewards

        // Now Alice tries to transfer remaining shares to Bob
        vm.prank(alice);
        vm.expectRevert(StakedKinto.CannotTransferAfterClaim.selector);
        vault.transfer(bob, 500);
    }

    /* ============ Edge Cases Tests ============ */

    function testZeroDeposit() public {
        vm.prank(alice);
        // Use expectRevert with the specific error message
        vm.expectRevert(abi.encodeWithSignature("DepositTooSmall()"));
        vault.deposit(0, alice);
    }

    function testDepositToOtherReceiver() public {
        vm.prank(alice);
        vault.deposit(1000 * 1e18, bob);

        assertEq(vault.balanceOf(bob), 1000 * 1e18);
        assertEq(vault.balanceOf(alice), 0);

        // Check user stake info is for bob, not alice
        (uint256 amount,,) = vault.getUserStakeInfo(bob, vault.currentPeriodId());
        assertEq(amount, 1000 * 1e18);

        (amount,,) = vault.getUserStakeInfo(alice, vault.currentPeriodId());
        assertEq(amount, 0);
    }

    function testWithdrawForOtherOwner() public {
        // Alice deposits
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);
        uint256 bobBalance = kToken.balanceOf(bob);

        // Advance time to after end date
        vm.warp(endTime + 1);

        // Start a new period so currentPid becomes 1
        vm.prank(admin);
        vault.startNewPeriod(block.timestamp + 30 days, 10, 1_000_000 ether, address(usdc));

        // Check the actual maxWithdraw value
        uint256 maxWithdrawAmount = vault.maxWithdraw(alice);

        // Alice approves bob to withdraw on her behalf
        vm.prank(alice);
        vault.approve(bob, 1000 * 1e18);

        // Bob withdraws on Alice's behalf (use the actual max amount)
        vm.prank(bob);
        vault.withdraw(maxWithdrawAmount, bob, alice);

        // Verify results
        assertEq(kToken.balanceOf(bob), bobBalance + maxWithdrawAmount);
        assertGt(usdc.balanceOf(bob), 0);
        assertEq(vault.balanceOf(alice), 0);
    }

    /* ======================= Helper ======================= */
    function _deposit(address user, uint256 amount) internal {
        vm.startPrank(user);
        kToken.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    function _depositWithBonus(address user, uint256 amount, uint256 untilPid) internal returns (uint256 shares) {
        uint256 diff = untilPid - vault.currentPeriodId();
        uint256 bonusPct = 5 * diff; // 5 % per future period
        uint256 amountWithBonus = amount + (amount * bonusPct) / 100;
        vm.startPrank(user);
        kToken.approve(address(vault), amountWithBonus);
        vault.depositWithBonus(amount, user, untilPid);
        (shares,,) = vault.getUserStakeInfo(user, vault.currentPeriodId());
        vm.stopPrank();
    }
}

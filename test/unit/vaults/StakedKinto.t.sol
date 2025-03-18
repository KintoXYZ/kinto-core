// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from 'forge-std/Test.sol';
import {ERC20Mock} from '@kinto-core-test/helpers/ERC20Mock.sol';
import {StakedKinto} from '@kinto-core/vaults/StakedKinto.sol';
import {UUPSProxy} from '@kinto-core-test/helpers/UUPSProxy.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {IERC20Upgradeable, IERC20MetadataUpgradeable} from
    '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol';
import {MathUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol';
import {SharedSetup} from '@kinto-core-test/SharedSetup.t.sol';

contract StakedKintoUpgraded is StakedKinto {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor() StakedKinto() {}
}

contract StakedKintoTest is SharedSetup {
    StakedKinto public vault;
    ERC20Mock public kToken; // Staking token
    ERC20Mock public usdc;   // Reward token
    
    address public admin = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public charlie = address(0x4);
    
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18; // 1 million K tokens
    uint256 public constant REWARD_AMOUNT = 100_000 * 1e6;     // 100,000 USDC
    uint256 public constant REWARD_RATE = 500;                 // 5% annual reward rate
    uint256 public constant MAX_CAPACITY = 500_000 * 1e18;     // 500,000 K tokens max capacity
    
    uint256 public startTime;
    uint256 public endTime;
    
    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);
        
        // Deploy mock tokens
        kToken = new ERC20Mock('Kinto Token', 'K', admin, INITIAL_SUPPLY);
        usdc = new ERC20Mock('USD Coin', 'USDC', admin, REWARD_AMOUNT);
        
        // Set timestamps for the vault
        startTime = block.timestamp;
        endTime = startTime + 365 days;
        
        // Deploy vault
        vault = new StakedKinto();
        vm.startPrank(admin);
        vault = StakedKinto(address(new UUPSProxy{salt: 0}(address(vault), '')));
        vault.initialize(
            IERC20MetadataUpgradeable(address(kToken)),
            IERC20Upgradeable(address(usdc)),
            REWARD_RATE,
            endTime,
            'Staked Kinto',
            'stK',
            MAX_CAPACITY
        );

        vm.stopPrank();
        // Transfer some tokens to test users
        kToken.mint(alice, 100_000 * 1e18);
        kToken.mint(bob, 100_000 * 1e18);
        kToken.mint(charlie, 100_000 * 1e18);
        
        // Transfer reward tokens to the vault
        usdc.transfer(address(vault), REWARD_AMOUNT);
        
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
    
    function testAsset() public {
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
        // Max mint should be equivalent to max deposit initially
        assertEq(vault.maxMint(alice), vault.convertToShares(MAX_CAPACITY));
        
        // Mint half the capacity
        vm.prank(alice);
        vault.mint(vault.convertToShares(MAX_CAPACITY / 2), alice);
        
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
        
        // Max withdraw should be the deposited amount
        assertEq(vault.maxWithdraw(alice), 1000 * 1e18);
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
    
    function testPreviewDeposit() public {
        // Preview deposit should match convertToShares
        assertEq(vault.previewDeposit(1000 * 1e18), vault.convertToShares(1000 * 1e18));
    }
    
    function testPreviewMint() public {
        // Preview mint should match convertToAssets for the inverse operation
        assertEq(vault.previewMint(1000 * 1e18), vault.convertToAssets(1000 * 1e18));
    }
    
    function testPreviewWithdraw() public {
        // Preview withdraw should match convertToShares for the inverse operation
        assertEq(vault.previewWithdraw(1000 * 1e18), vault.convertToShares(1000 * 1e18));
    }
    
    function testPreviewRedeem() public {
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
        (uint256 amount, uint256 weightedTimestamp, ) = vault.getUserStakeInfo(alice);
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
        (uint256 amount, uint256 weightedTimestamp, ) = vault.getUserStakeInfo(alice);
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
        vm.expectRevert(abi.encodeWithSignature('MaxCapacityReached()'));
        vault.deposit(1000 * 1e18, bob);
    }
    
    function testDepositAfterEndDate() public {
        // Advance time to after end date
        vm.warp(endTime + 1);
        
        // Try to deposit
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature('StakingPeriodEnded()'));
        vault.deposit(1000 * 1e18, alice);
    }
    
    /* ============ Withdraw/Redeem Tests ============ */
    
    function testWithdrawBeforeEndDate() public {
        // Deposit
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);
        
        // Try to withdraw before end date
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature('CannotWithdrawBeforeEndDate()'));
        vault.withdraw(1000 * 1e18, alice, alice);
    }
    
    function testWithdrawAfterEndDate() public {
        // Deposit
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);
        
        // Advance time to after end date
        vm.warp(endTime + 1);
        
        // Withdraw
        vm.prank(alice);
        uint256 assets = vault.withdraw(1000 * 1e18, alice, alice);
        
        assertEq(assets, 1000 * 1e18);
        assertEq(kToken.balanceOf(alice), 100_000 * 1e18); // Original balance restored
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
        vm.expectRevert(abi.encodeWithSignature('CannotRedeemBeforeEndDate()'));
        vault.redeem(1000 * 1e18, alice, alice);
    }
    
    function testRedeemAfterEndDate() public {
        // Deposit
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);
        
        // Advance time to after end date
        vm.warp(endTime + 1);
        
        // Redeem
        vm.prank(alice);
        uint256 assets = vault.redeem(1000 * 1e18, alice, alice);
        
        assertEq(assets, 1000 * 1e18);
        assertEq(kToken.balanceOf(alice), 100_000 * 1e18); // Original balance restored
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalAssets(), 0);
        
        // Check rewards
        assertGt(usdc.balanceOf(alice), 0); // Should have received some rewards
    }
    
    /* ============ Rewards Tests ============ */
    
    function testCalculateRewards() public {
        // Deposit
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);
        
        // Initial rewards should be 0
        assertEq(vault.calculateRewards(alice), 0);
        
        // Advance time by 6 months
        vm.warp(block.timestamp + 182 days);
        
        // Calculate expected rewards: amount * rate * duration / (365 days * 100)
        uint256 expectedRewards = (1000 * 1e18 * REWARD_RATE * 182 days) / (365 days * 100);
        assertApproxEqAbs(vault.calculateRewards(alice), expectedRewards, 10); // Allow small rounding difference
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
        
        assertEq(vault.maxCapacity(), newCapacity);
        assertEq(vault.maxDeposit(alice), newCapacity);
    }
    
    function testSetMaxCapacityUnauthorized() public {
        vm.prank(alice);
        vm.expectRevert(); // Should revert with Ownable error
        vault.setMaxCapacity(1_000_000 * 1e18);
    }
    
    function testUpgrade() public {
        // This would require a mock implementation contract to test properly
        // Just verify the function exists and is restricted to owner
        vm.prank(alice);
        vm.expectRevert(); // Should revert with Ownable error
        vault._authorizeUpgrade(address(0x123));
    }

    function testUpgradeTo() public {
        StakedKinto _implementationV2 = new StakedKintoUpgraded();
        vm.prank(vault.owner());
        vault.upgradeTo(address(_implementationV2));
        assertEq(StakedKintoUpgraded(address(vault)).newFunction(), 1);
    }

    
    /* ============ Edge Cases Tests ============ */
    
    function testZeroDeposit() public {
        vm.prank(alice);
        vm.expectRevert(); // Should revert with arithmetic error
        vault.deposit(0, alice);
    }
    
    function testDepositToOtherReceiver() public {
        vm.prank(alice);
        vault.deposit(1000 * 1e18, bob);
        
        assertEq(vault.balanceOf(bob), 1000 * 1e18);
        assertEq(vault.balanceOf(alice), 0);
        
        // Check user stake info is for bob, not alice
        (uint256 amount, , ) = vault.getUserStakeInfo(bob);
        assertEq(amount, 1000 * 1e18);
        
        (amount, , ) = vault.getUserStakeInfo(alice);
        assertEq(amount, 0);
    }
    
    function testWithdrawForOtherOwner() public {
        // Alice deposits
        vm.prank(alice);
        vault.deposit(1000 * 1e18, alice);
        
        // Advance time to after end date
        vm.warp(endTime + 1);
        
        // Alice approves bob to withdraw on her behalf
        vm.prank(alice);
        vault.approve(bob, 1000 * 1e18);
        
        // Bob withdraws on Alice's behalf
        vm.prank(bob);
        vault.withdraw(1000 * 1e18, bob, alice);
        
        // Bob should receive the assets and rewards
        assertEq(kToken.balanceOf(bob), 100_000 * 1e18 + 1000 * 1e18);
        assertGt(usdc.balanceOf(bob), 0);
        
        // Alice's vault balance should be 0
        assertEq(vault.balanceOf(alice), 0);
    }
}

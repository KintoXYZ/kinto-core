// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin-5.0.1/contracts/utils/cryptography/ECDSA.sol";
import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";

import {ForkTest} from "@kinto-core-test/helpers/ForkTest.sol";
import {ERC20Mock} from "@kinto-core-test/helpers/ERC20Mock.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";

import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";

contract RewardsDistributorTest is SharedSetup {
    RewardsDistributor internal distributor;
    ERC20Mock internal kinto;
    bytes32 internal root = 0x4f75b6d95fab3aedde221f8f5020583b4752cbf6a155ab4e5405fe92881f80e6;
    bytes32 internal leaf;
    uint256 internal bonusAmount = 600_000e18;
    uint256 internal startTime = START_TIMESTAMP;

    // Helper function to mock correct Merkle proofs for a given user and amount
    function _setupNewMerkleRoot(address user, uint256 amount) internal returns (bytes32[] memory) {
        // Create a mock proof
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = keccak256(abi.encode("test proof"));

        // Create a leaf node
        bytes32 newLeaf = keccak256(bytes.concat(keccak256(abi.encode(user, amount))));

        // Create a new root that will validate with the proof and leaf
        bytes32 newRoot = keccak256(abi.encode(newLeaf, proof[0]));

        // Set the new root
        vm.prank(_owner);
        distributor.updateRoot(newRoot);

        return proof;
    }

    function setUp() public override {
        super.setUp();

        kinto = new ERC20Mock("Kinto Token", "KINTO", 18);

        vm.startPrank(_owner);
        distributor = RewardsDistributor(
            address(
                new UUPSProxy{salt: 0}(address(new RewardsDistributor(kinto, startTime, address(_walletFactory))), "")
            )
        );
        distributor.initialize(root, bonusAmount);
        vm.stopPrank();
    }

    function testUp() public override {
        vm.startPrank(_owner);
        distributor = RewardsDistributor(
            address(
                new UUPSProxy{salt: 0}(address(new RewardsDistributor(kinto, startTime, address(_walletFactory))), "")
            )
        );
        distributor.initialize(root, bonusAmount);
        vm.stopPrank();

        assertEq(distributor.startTime(), START_TIMESTAMP);
        assertEq(address(distributor.KINTO()), address(kinto));
        assertEq(distributor.root(), root);
        assertEq(distributor.totalClaimed(), 0);
        assertEq(distributor.bonusAmount(), bonusAmount);
        assertEq(distributor.getTotalLimit(), bonusAmount);
        assertEq(distributor.getUnclaimedLimit(), bonusAmount);
    }

    function testClaim() public {
        uint256 amount = 1e18;

        kinto.mint(address(distributor), amount);

        assertEq(kinto.balanceOf(address(distributor)), amount);
        assertEq(kinto.balanceOf(_user), 0);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0xb92c48e9d7abe27fd8dfd6b5dfdbfb1c9a463f80c712b66f3a5180a090cccafc;
        proof[1] = 0xfe69d275d3541c8c5338701e9b211e3fc949b5efb1d00a410313e7474952967f;

        vm.expectEmit(true, true, true, true);
        emit RewardsDistributor.UserClaimed(_user, amount);
        distributor.claim(proof, _user, amount);

        assertEq(kinto.balanceOf(address(distributor)), 0);
        assertEq(kinto.balanceOf(_user), amount);
        assertEq(distributor.totalClaimed(), amount);
        assertEq(distributor.claimedByUser(_user), amount);
        assertEq(distributor.getTotalLimit(), bonusAmount);
        assertEq(distributor.getUnclaimedLimit(), bonusAmount - amount);
        assertEq(distributor.claimedRoot(_user), distributor.root());
    }

    function testClaimTwoRoots() public {
        uint256 amount = 1e18;

        kinto.mint(address(distributor), amount * 2);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0xb92c48e9d7abe27fd8dfd6b5dfdbfb1c9a463f80c712b66f3a5180a090cccafc;
        proof[1] = 0xfe69d275d3541c8c5338701e9b211e3fc949b5efb1d00a410313e7474952967f;

        distributor.claim(proof, _user, amount);

        assertEq(distributor.claimedRoot(_user), distributor.root());

        vm.prank(_owner);
        distributor.updateRoot(0xdf8a56a37f21e52f6b05dc585fd82d58fc6d22def694773b1908e37c01dd956e);

        proof = new bytes32[](1);
        proof[0] = 0xf99b282683659c94d424bb86cf2a97562a08a76b5aee76ae401a001c75ca8f02;

        distributor.claim(proof, _user, amount * 2);

        assertEq(kinto.balanceOf(address(distributor)), 0);
        assertEq(kinto.balanceOf(_user), amount * 2);
        assertEq(distributor.totalClaimed(), amount * 2);
        assertEq(distributor.claimedByUser(_user), amount * 2);
        assertEq(distributor.getTotalLimit(), bonusAmount);
        assertEq(distributor.getUnclaimedLimit(), bonusAmount - amount * 2);
        assertEq(distributor.claimedRoot(_user), distributor.root());
    }

    function testClaim_RevertWhenClaimedTwice() public {
        uint256 amount = 1e18;

        kinto.mint(address(distributor), 2 * amount);

        assertEq(kinto.balanceOf(address(distributor)), 2 * amount);
        assertEq(kinto.balanceOf(_user), 0);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0xb92c48e9d7abe27fd8dfd6b5dfdbfb1c9a463f80c712b66f3a5180a090cccafc;
        proof[1] = 0xfe69d275d3541c8c5338701e9b211e3fc949b5efb1d00a410313e7474952967f;

        distributor.claim(proof, _user, amount);

        vm.expectRevert(abi.encodeWithSelector(RewardsDistributor.RootAlreadyClaimed.selector, _user));
        distributor.claim(proof, _user, amount);
    }

    function testClaim_WhenTimePass() public {
        uint256 amount = 1e18;

        vm.prank(_owner);
        distributor.updateBonusAmount(0);

        kinto.mint(address(distributor), amount);

        assertEq(kinto.balanceOf(address(distributor)), amount);
        assertEq(kinto.balanceOf(_user), 0);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0xb92c48e9d7abe27fd8dfd6b5dfdbfb1c9a463f80c712b66f3a5180a090cccafc;
        proof[1] = 0xfe69d275d3541c8c5338701e9b211e3fc949b5efb1d00a410313e7474952967f;

        vm.warp(START_TIMESTAMP + amount / (distributor.rewardsPerQuarter(0) / (90 days)) + 1);

        distributor.claim(proof, _user, amount);

        assertEq(kinto.balanceOf(address(distributor)), 0);
        assertEq(kinto.balanceOf(_user), amount);
        assertEq(distributor.totalClaimed(), amount);
        assertEq(distributor.claimedByUser(_user), amount);
        assertEq(distributor.getTotalLimit(), 1004311189496374701);
        assertEq(distributor.getUnclaimedLimit(), 4311189496374701);
    }

    function testClaimMultiple() public {
        uint256 amount = 1e18;

        kinto.mint(address(distributor), amount);

        assertEq(kinto.balanceOf(address(distributor)), amount);
        assertEq(kinto.balanceOf(_user), 0);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0xb92c48e9d7abe27fd8dfd6b5dfdbfb1c9a463f80c712b66f3a5180a090cccafc;
        proof[1] = 0xfe69d275d3541c8c5338701e9b211e3fc949b5efb1d00a410313e7474952967f;

        distributor.claim(proof, _user, amount);

        assertEq(kinto.balanceOf(address(distributor)), 0);
        assertEq(kinto.balanceOf(_user), amount);
        assertEq(distributor.totalClaimed(), amount);
        assertEq(distributor.claimedByUser(_user), amount);
        assertEq(distributor.getTotalLimit(), bonusAmount);
        assertEq(distributor.getUnclaimedLimit(), bonusAmount - amount);

        uint256 secondAmount = 2500000000000000000;
        address second = 0x2222222222222222222222222222222222222222;
        kinto.mint(address(distributor), secondAmount);

        proof[0] = 0xf99b282683659c94d424bb86cf2a97562a08a76b5aee76ae401a001c75ca8f02;
        proof[1] = 0xfe69d275d3541c8c5338701e9b211e3fc949b5efb1d00a410313e7474952967f;

        distributor.claim(proof, second, secondAmount);

        assertEq(kinto.balanceOf(address(distributor)), 0);
        assertEq(kinto.balanceOf(_user), amount);
        assertEq(kinto.balanceOf(second), secondAmount);
        assertEq(distributor.totalClaimed(), amount + secondAmount);
        assertEq(distributor.claimedByUser(_user), amount);
        assertEq(distributor.claimedByUser(second), secondAmount);
        assertEq(distributor.getTotalLimit(), bonusAmount);
        assertEq(distributor.getUnclaimedLimit(), bonusAmount - (amount + secondAmount));
        assertEq(distributor.claimedRoot(_user), distributor.root());
        assertEq(distributor.claimedRoot(second), distributor.root());
    }

    function testClaim_RevertWhenInvalidProof() public {
        uint256 amount = 1e18;

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        leaf = keccak256(bytes.concat(keccak256(abi.encode(_user, amount))));
        vm.expectRevert(abi.encodeWithSelector(RewardsDistributor.InvalidProof.selector, proof, leaf));

        distributor.claim(proof, _user, amount);
    }

    function testClaim_RevertWhenMaxLimitExceeded() public {
        vm.startPrank(_owner);
        RewardsDistributor distr = RewardsDistributor(
            address(
                new UUPSProxy{salt: 0}(address(new RewardsDistributor(kinto, startTime, address(_walletFactory))), "")
            )
        );
        distr.initialize(root, 0);
        vm.stopPrank();
        uint256 amount = 1e18;

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0xb92c48e9d7abe27fd8dfd6b5dfdbfb1c9a463f80c712b66f3a5180a090cccafc;
        proof[1] = 0xfe69d275d3541c8c5338701e9b211e3fc949b5efb1d00a410313e7474952967f;

        vm.expectRevert(abi.encodeWithSelector(RewardsDistributor.MaxLimitReached.selector, amount, 0));
        distr.claim(proof, _user, amount);
    }

    function testClaim_RevertWhenAlreadyClaimed() public {
        uint256 amount = 1e18;

        kinto.mint(address(distributor), amount);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0xb92c48e9d7abe27fd8dfd6b5dfdbfb1c9a463f80c712b66f3a5180a090cccafc;
        proof[1] = 0xfe69d275d3541c8c5338701e9b211e3fc949b5efb1d00a410313e7474952967f;

        distributor.claim(proof, _user, amount);

        vm.prank(_owner);
        distributor.updateRoot(0xdf8a56a37f21e52f6b05dc585fd82d58fc6d22def694773b1908e37c01dd956e);

        proof[0] = 0xb92c48e9d7abe27fd8dfd6b5dfdbfb1c9a463f80c712b66f3a5180a090cccafc;
        proof[1] = 0xfe69d275d3541c8c5338701e9b211e3fc949b5efb1d00a410313e7474952967f;

        vm.expectRevert(abi.encodeWithSelector(RewardsDistributor.AlreadyClaimed.selector, _user));
        distributor.claim(proof, _user, amount);
    }

    function testUpdateRoot() public {
        bytes32 newRoot = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

        vm.expectEmit(true, true, true, true);
        emit RewardsDistributor.RootUpdated(newRoot, root);
        vm.prank(_owner);
        distributor.updateRoot(newRoot);

        assertEq(distributor.root(), newRoot);
    }

    function testUpdateRoot_RevertWhenNotOwner() public {
        bytes32 newRoot = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), distributor.UPDATER_ROLE()
            )
        );
        distributor.updateRoot(newRoot);
    }

    function testUpdateBonusAmount() public {
        uint256 newBonusAmount = 1_000_000e18;

        vm.expectEmit(true, true, true, true);
        emit RewardsDistributor.BonusAmountUpdated(newBonusAmount, bonusAmount);
        vm.prank(_owner);
        distributor.updateBonusAmount(newBonusAmount);

        assertEq(distributor.bonusAmount(), newBonusAmount);
    }

    function testUpdateBonusAmount_RevertWhenNotOwner() public {
        uint256 newBonusAmount = 1_000_000e18;

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(this),
                distributor.DEFAULT_ADMIN_ROLE()
            )
        );
        distributor.updateBonusAmount(newBonusAmount);
    }

    function testTotalLimitPerQuarter() public {
        vm.startPrank(_owner);
        RewardsDistributor distr = RewardsDistributor(
            address(
                new UUPSProxy{salt: 0}(address(new RewardsDistributor(kinto, startTime, address(_walletFactory))), "")
            )
        );
        distr.initialize(root, 0);
        vm.stopPrank();

        uint256[] memory values = new uint256[](40);
        values[0] = 190_476190476190480000000; // 190_476.19047619048
        values[1] = 181_405895691609980000000;
        values[2] = 172_767519706295220000000;
        values[3] = 164_540494958376400000000;
        values[4] = 156_705233293691808000000;
        values[5] = 149_243079327325532000000;
        values[6] = 142_136266026024316000000;
        values[7] = 135_367872405737444000000;
        values[8] = 128_921783243559468000000;
        values[9] = 122_782650708151876000000;
        values[10] = 116_935857817287500000000;
        values[11] = 111_367483635511904000000;
        values[12] = 106_064270129058956000000;
        values[13] = 101_013590599103768000000;
        values[14] = 962_03419618194068000000;
        values[15] = 916_22304398280064000000;
        values[16] = 87_259337522171488000000;
        values[17] = 83_104130973496656000000;
        values[18] = 79_146791403330148000000;
        values[19] = 75_377896574600140000000;
        values[20] = 71_788472928190612000000;
        values[21] = 68_369974217324392000000;
        values[22] = 65_114261159356564000000;
        values[23] = 62_013582056530060000000;
        values[24] = 59_060554339552436000000;
        values[25] = 56_248146990049940000000;
        values[26] = 53_569663800047564000000;
        values[27] = 51_018727428616728000000;
        values[28] = 48_589264217730216000000;
        values[29] = 46_275489731171632000000;
        values[30] = 44_071894982068224000000;
        values[31] = 41_973233316255452000000;
        values[32] = 39_974507920243284000000;
        values[33] = 38_070959924041224000000;
        values[34] = 36_258057070515452000000;
        values[35] = 34_531482924300432000000;
        values[36] = 32_887126594571840000000;
        values[37] = 31_321072947211276000000;
        values[38] = 29_829593283058356000000;
        values[39] = 28_409136460055580000000; // 28_409.13646005558

        for (uint256 e = 0; e < distr.quarters(); e++) {
            vm.warp(START_TIMESTAMP + (90 days) * (e + 1));
            assertEq(distr.rewardsPerQuarter(e), values[e]);

            uint256 expectedTotalLimit;
            for (uint256 i = 0; i <= e; i++) {
                expectedTotalLimit += distr.rewardsPerQuarter(i);
            }
            if (e != 39) {
                assertEq(distr.getTotalLimit(), expectedTotalLimit);
            } else {
                assertEq(distr.getTotalLimit(), 4_000_000 * 1e18);
            }
        }

        // check that limit is 4mil even after 10 years.
        vm.warp(START_TIMESTAMP + (365 days) * 10);
        assertEq(distr.getTotalLimit(), 4_000_000 * 1e18);
    }

    function testGetRewards() public view {
        assertEq(distributor.getRewards(0, START_TIMESTAMP), 0);
        assertEq(distributor.getRewards(START_TIMESTAMP, START_TIMESTAMP), 0);
        assertEq(distributor.getRewards(START_TIMESTAMP, START_TIMESTAMP + 24 * 3600), 2116402116402116444444); // 2116 for a day
        assertEq(distributor.getRewards(START_TIMESTAMP, START_TIMESTAMP + 30 * 24 * 3600), 63492063492063493333333); // 63k for a first 30 days
        assertEq(distributor.getRewards(START_TIMESTAMP, START_TIMESTAMP + 90 * 24 * 3600), 190476190476190480000000); // 190k for a first 90 days
        assertEq(
            distributor.getRewards(
                START_TIMESTAMP + 10 * 90 * 24 * 3600, START_TIMESTAMP + 10 * 90 * 24 * 3600 + 30 * 24 * 3600
            ),
            38978619272429166666666
        ); // 39k for a 30 days in 11'th quarter
    }

    function testDailyLimit() public {
        uint256 belowLimit = 4000 * 1e18; // 4000 Kinto tokens (below the 5000 limit)
        uint256 exactLimit = 5000 * 1e18; // Exactly 5000 Kinto tokens
        uint256 aboveLimit = 6000 * 1e18; // 6000 Kinto tokens (above the 5000 limit)

        // Mint enough tokens to the distributor
        kinto.mint(address(distributor), aboveLimit);

        // Set up valid merkle proof for the first claim
        bytes32[] memory proof = _setupNewMerkleRoot(_user, belowLimit);

        // Claim below the daily limit should succeed
        vm.expectEmit(true, true, true, true);
        emit RewardsDistributor.UserClaimed(_user, belowLimit);
        distributor.claim(proof, _user, belowLimit);

        // Verify claim data was updated correctly
        assertEq(kinto.balanceOf(_user), belowLimit);
        assertEq(distributor.totalClaimed(), belowLimit);
        assertEq(distributor.claimedByUser(_user), belowLimit);
        assertEq(distributor.lastClaimTimestamp(_user), block.timestamp);
        assertEq(distributor.dailyClaimedAmount(_user), belowLimit);

        // Verify remaining daily claimable amount
        assertEq(distributor.getDailyRemainingClaimable(_user), exactLimit - belowLimit);

        // Set up valid merkle proof for the second claim
        proof = _setupNewMerkleRoot(_user, aboveLimit);

        // Claim more than the remaining daily limit - should transfer available limit only
        uint256 remainingAmount = exactLimit - belowLimit;
        vm.expectEmit(true, true, true, true);
        emit RewardsDistributor.UserClaimed(_user, remainingAmount);
        distributor.claim(proof, _user, aboveLimit);

        // Verify claim data was updated correctly - should show only the daily limit was claimed
        assertEq(kinto.balanceOf(_user), exactLimit);
        assertEq(distributor.totalClaimed(), exactLimit);
        assertEq(distributor.claimedByUser(_user), exactLimit);
        assertEq(distributor.dailyClaimedAmount(_user), exactLimit);

        // Verify daily limit is now fully used
        assertEq(distributor.getDailyRemainingClaimable(_user), 0);
    }

    function testDailyLimitReset() public {
        uint256 exactLimit = 5000 * 1e18; // Exactly 5000 Kinto tokens

        // Mint enough tokens to the distributor
        kinto.mint(address(distributor), exactLimit * 2);

        // Set up valid merkle proof for the first claim
        bytes32[] memory proof = _setupNewMerkleRoot(_user, exactLimit);

        // Claim the full daily limit
        distributor.claim(proof, _user, exactLimit);

        // Verify user claimed the full daily limit
        assertEq(kinto.balanceOf(_user), exactLimit);
        assertEq(distributor.dailyClaimedAmount(_user), exactLimit);
        assertEq(distributor.getDailyRemainingClaimable(_user), 0);

        // Advance time by 1 day
        vm.warp(block.timestamp + distributor.ONE_DAY());

        // Set up valid merkle proof for the second claim
        proof = _setupNewMerkleRoot(_user, exactLimit * 2);

        // Verify daily limit has reset
        assertEq(distributor.getDailyRemainingClaimable(_user), exactLimit);

        // User should be able to claim again up to the daily limit
        vm.expectEmit(true, true, true, true);
        emit RewardsDistributor.UserClaimed(_user, exactLimit);
        distributor.claim(proof, _user, exactLimit * 2);

        // Verify the second claim was successful
        assertEq(kinto.balanceOf(_user), exactLimit * 2);
        assertEq(distributor.claimedByUser(_user), exactLimit * 2);
        assertEq(distributor.dailyClaimedAmount(_user), exactLimit);
    }

    function testPartialDayPassing() public {
        uint256 halfLimit = 2500 * 1e18; // Half of the daily limit

        // Mint enough tokens to the distributor
        kinto.mint(address(distributor), halfLimit * 4);

        // Set up valid merkle proof for the first claim
        bytes32[] memory proof = _setupNewMerkleRoot(_user, halfLimit);

        // First claim of half the limit
        distributor.claim(proof, _user, halfLimit);

        // Verify user claimed half the daily limit
        assertEq(distributor.dailyClaimedAmount(_user), halfLimit);
        assertEq(distributor.getDailyRemainingClaimable(_user), halfLimit);

        // Advance time by 12 hours (less than a day)
        vm.warp(block.timestamp + distributor.ONE_DAY() / 2);

        // Set up valid merkle proof for the second claim
        proof = _setupNewMerkleRoot(_user, halfLimit * 2);

        // Verify daily limit hasn't reset (still half remaining)
        assertEq(distributor.getDailyRemainingClaimable(_user), halfLimit);

        // Claim the remaining half
        distributor.claim(proof, _user, halfLimit * 2);

        // Verify user has now claimed the full daily limit
        assertEq(kinto.balanceOf(_user), halfLimit * 2);
        assertEq(distributor.dailyClaimedAmount(_user), halfLimit * 2);
        assertEq(distributor.getDailyRemainingClaimable(_user), 0);

        // Advance time to just before the day completes
        vm.warp(block.timestamp + distributor.ONE_DAY() / 2 - 1);

        // Verify daily limit still hasn't reset
        assertEq(distributor.getDailyRemainingClaimable(_user), 0);

        // Advance time to just after the day completes
        vm.warp(block.timestamp + 2);

        // Check if daily limit has reset
        uint256 newRemainingLimit = distributor.getDailyRemainingClaimable(_user);
        assertTrue(newRemainingLimit > 0, "Daily limit should have reset");
        assertEq(newRemainingLimit, distributor.DAILY_CLAIM_LIMIT());
    }

    function testWhitelistAddAndRemove() public {
        address whitelistUser = address(0xABCD);

        // Initially user should not be whitelisted
        vm.prank(_owner);
        assertFalse(distributor.isClaimWhitelisted(whitelistUser));

        // Add user to whitelist
        vm.prank(_owner);
        vm.expectEmit(true, false, false, false);
        emit RewardsDistributor.WalletClaimWhitelistAdded(whitelistUser);
        distributor.addToClaimWhitelist(whitelistUser);

        // Verify user is now whitelisted
        vm.prank(_owner);
        assertTrue(distributor.isClaimWhitelisted(whitelistUser));

        // Remove user from whitelist
        vm.prank(_owner);
        vm.expectEmit(true, false, false, false);
        emit RewardsDistributor.WalletClaimWhitelistRemoved(whitelistUser);
        distributor.removeFromClaimWhitelist(whitelistUser);

        // Verify user is no longer whitelisted
        vm.prank(_owner);
        assertFalse(distributor.isClaimWhitelisted(whitelistUser));
    }

    function testWhitelistAccessControl() public {
        address whitelistUser = address(0xABCD);
        address nonAdmin = address(0x1234);

        // Non-admin should not be able to add to whitelist
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, distributor.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(nonAdmin);
        distributor.addToClaimWhitelist(whitelistUser);

        // Non-admin should not be able to remove from whitelist
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, distributor.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(nonAdmin);
        distributor.removeFromClaimWhitelist(whitelistUser);

        // Admin should be able to add to whitelist
        vm.prank(_owner);
        distributor.addToClaimWhitelist(whitelistUser);

        // Verify user is now whitelisted
        vm.prank(_owner);
        assertTrue(distributor.isClaimWhitelisted(whitelistUser));
    }

    function testClaimWhitelistArray() public {
        // Add multiple users to the whitelist
        address[] memory usersToWhitelist = new address[](3);
        usersToWhitelist[0] = address(0xABCD);
        usersToWhitelist[1] = address(0x1234);
        usersToWhitelist[2] = address(0x5678);

        vm.startPrank(_owner);
        for (uint256 i = 0; i < usersToWhitelist.length; i++) {
            distributor.addToClaimWhitelist(usersToWhitelist[i]);
        }
        vm.stopPrank();

        // Get the whitelist array
        address[] memory whitelistedAddresses = distributor.claimWhitelist();

        // Verify the correct number of addresses
        assertEq(whitelistedAddresses.length, usersToWhitelist.length);

        // Verify each user is in the whitelist
        for (uint256 i = 0; i < usersToWhitelist.length; i++) {
            bool foundUser = false;
            for (uint256 j = 0; j < whitelistedAddresses.length; j++) {
                if (whitelistedAddresses[j] == usersToWhitelist[i]) {
                    foundUser = true;
                    break;
                }
            }
            assertTrue(foundUser, "User not found in whitelist array");
        }
    }

    function testWhitelistedUserCanBypassDailyLimit() public {
        address whitelistedUser = address(0xABCD);
        uint256 dailyLimit = distributor.DAILY_CLAIM_LIMIT();
        uint256 aboveLimit = dailyLimit * 2; // Double the daily limit

        // Add user to whitelist
        vm.prank(_owner);
        distributor.addToClaimWhitelist(whitelistedUser);

        // Mint tokens to the distributor
        kinto.mint(address(distributor), aboveLimit);

        // Set up valid merkle proof for the claim
        bytes32[] memory proof = _setupNewMerkleRoot(whitelistedUser, aboveLimit);

        // Whitelisted user should be able to claim above the daily limit
        distributor.claim(proof, whitelistedUser, aboveLimit);

        // Verify the whitelisted user received the full amount despite it being above the daily limit
        assertEq(kinto.balanceOf(whitelistedUser), aboveLimit);

        // Verify the daily remaining claimable shows max uint256 for whitelisted user
        assertEq(distributor.getDailyRemainingClaimable(whitelistedUser), type(uint256).max);
    }

    function testNonWhitelistedVsWhitelistedClaims() public {
        address normalUser = address(0x1111);
        address whitelistedUser = address(0xABCD);
        uint256 dailyLimit = distributor.DAILY_CLAIM_LIMIT();
        uint256 aboveLimit = dailyLimit * 2; // Double the daily limit

        // Add only one user to whitelist
        vm.prank(_owner);
        distributor.addToClaimWhitelist(whitelistedUser);

        // Mint tokens to the distributor for both users
        kinto.mint(address(distributor), aboveLimit * 2);

        // Set up valid merkle proofs for both users
        bytes32[] memory proofNormal = _setupNewMerkleRoot(normalUser, aboveLimit);
        // Normal user should be limited by daily limit
        distributor.claim(proofNormal, normalUser, aboveLimit);

        bytes32[] memory proofWhitelisted = _setupNewMerkleRoot(whitelistedUser, aboveLimit);

        // Whitelisted user should get full amount
        distributor.claim(proofWhitelisted, whitelistedUser, aboveLimit);

        // Verify normal user only received the daily limit
        assertEq(kinto.balanceOf(normalUser), dailyLimit);

        // Verify whitelisted user received the full amount
        assertEq(kinto.balanceOf(whitelistedUser), aboveLimit);
    }

    function testRemovingFromWhitelistEnforcesDailyLimit() public {
        address user = address(0xABCD);
        uint256 dailyLimit = distributor.DAILY_CLAIM_LIMIT();
        uint256 halfLimit = dailyLimit / 2;
        uint256 aboveLimit = dailyLimit * 2; // Double the daily limit

        // Mint tokens to the distributor
        kinto.mint(address(distributor), aboveLimit);

        // Add user to whitelist
        vm.prank(_owner);
        distributor.addToClaimWhitelist(user);

        // Set up valid merkle proof for the first claim
        bytes32[] memory proof = _setupNewMerkleRoot(user, halfLimit);

        // User should be able to claim while whitelisted
        distributor.claim(proof, user, halfLimit);

        // Remove user from whitelist
        vm.prank(_owner);
        distributor.removeFromClaimWhitelist(user);

        // Set up valid merkle proof for the second claim, now exceeding daily limit when combined
        proof = _setupNewMerkleRoot(user, halfLimit + dailyLimit);

        // User should only be able to claim up to daily limit now
        distributor.claim(proof, user, halfLimit + dailyLimit);

        // Verify user received half limit from first claim plus remaining half from second claim
        assertEq(kinto.balanceOf(user), dailyLimit);
    }

    function testMultiDayClaim() public {
        uint256 exactLimit = 5000 * 1e18; // Exactly 5000 Kinto tokens (daily limit)
        uint256 largeAmount = 12000 * 1e18; // 12000 Kinto tokens (multiple days worth)

        // Mint enough tokens to the distributor
        kinto.mint(address(distributor), largeAmount);

        // Day 1: First claim - should get exactly the daily limit
        bytes32[] memory proof = _setupNewMerkleRoot(_user, exactLimit);

        vm.expectEmit(true, true, true, true);
        emit RewardsDistributor.UserClaimed(_user, exactLimit);
        distributor.claim(proof, _user, exactLimit);

        // Verify user received the daily limit
        assertEq(kinto.balanceOf(_user), exactLimit);
        assertEq(distributor.dailyClaimedAmount(_user), exactLimit);
        assertEq(distributor.claimedByUser(_user), exactLimit);

        // Advance to day 2
        vm.warp(block.timestamp + distributor.ONE_DAY() + 1);

        // Day 2: Second claim - another exactLimit
        proof = _setupNewMerkleRoot(_user, exactLimit * 2);

        vm.expectEmit(true, true, true, true);
        emit RewardsDistributor.UserClaimed(_user, exactLimit);
        distributor.claim(proof, _user, exactLimit * 2);

        // Verify user received another daily limit
        assertEq(kinto.balanceOf(_user), exactLimit * 2);
        assertEq(distributor.dailyClaimedAmount(_user), exactLimit);
        assertEq(distributor.claimedByUser(_user), exactLimit * 2);

        // Advance to day 3
        vm.warp(block.timestamp + distributor.ONE_DAY() + 1);

        // Day 3: Final claim - remaining 2000 tokens
        uint256 remaining = largeAmount - (exactLimit * 2);
        proof = _setupNewMerkleRoot(_user, largeAmount);

        vm.expectEmit(true, true, true, true);
        emit RewardsDistributor.UserClaimed(_user, remaining);
        distributor.claim(proof, _user, largeAmount);

        // Verify user received the final remaining amount
        assertEq(kinto.balanceOf(_user), largeAmount);
        assertEq(distributor.dailyClaimedAmount(_user), remaining);
        assertEq(distributor.claimedByUser(_user), largeAmount);
        assertEq(distributor.getDailyRemainingClaimable(_user), exactLimit - remaining);
    }
}

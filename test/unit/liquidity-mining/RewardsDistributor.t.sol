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

    function testNewUserClaim_RevertWhen_NotFactory() public {
        vm.expectRevert(abi.encodeWithSelector(RewardsDistributor.OnlyWalletFactory.selector, address(this)));
        distributor.newUserClaim(address(_kintoWallet));
    }

    function testNewUserClaim_RevertWhen_AlreadyClaimed() public {
        vm.prank(address(_owner));
        _kintoWallet = _walletFactory.createAccount(_owner, _owner, 0);

        vm.expectRevert(abi.encodeWithSelector(RewardsDistributor.AlreadyClaimed.selector, address(_kintoWallet)));
        vm.prank(address(_walletFactory));
        _rewardsDistributor.newUserClaim(address(_kintoWallet));
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin-5.0.1/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";

import {ForkTest} from "@kinto-core-test/helpers/ForkTest.sol";
import {ERC20Mock} from "@kinto-core-test/helpers/ERC20Mock.sol";

import {RewardsDistributor} from "@kinto-core/RewardsDistributor.sol";

contract RewardsDistributorTest is ForkTest {
    RewardsDistributor internal distributor;
    ERC20Mock internal kinto;
    ERC20Mock internal engen;
    bytes32 internal root = 0x4f75b6d95fab3aedde221f8f5020583b4752cbf6a155ab4e5405fe92881f80e6;
    bytes32 internal leaf;
    uint256 internal bonusAmount = 600_000e18;
    uint256 internal startTime = START_TIMESTAMP;

    function setUp() public override {
        super.setUp();

        kinto = new ERC20Mock("Kinto Token", "KINTO", 18);
        engen = new ERC20Mock("Engen Token", "ENGEN", 18);

        vm.prank(_owner);
        distributor = new RewardsDistributor(kinto, engen, root, bonusAmount, startTime);
    }

    function testUp() public override {
        distributor = new RewardsDistributor(kinto, engen, root, bonusAmount, startTime);

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

        console2.log("distributor.rewardsPerQuarter(0):", distributor.rewardsPerQuarter(0));
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

        kinto.mint(address(distributor), amount);

        proof[0] = 0xf99b282683659c94d424bb86cf2a97562a08a76b5aee76ae401a001c75ca8f02;
        proof[1] = 0xf5d3a04b6083ba8077d903785b3001db5b9077f1a3af3e06d27a8a9fa3567546;

        distributor.claim(proof, _user, amount);

        assertEq(kinto.balanceOf(address(distributor)), 0);
        assertEq(kinto.balanceOf(_user), 2 * amount);
        assertEq(distributor.totalClaimed(), 2 * amount);
        assertEq(distributor.claimedByUser(_user), 2 * amount);
        assertEq(distributor.getTotalLimit(), bonusAmount);
        assertEq(distributor.getUnclaimedLimit(), bonusAmount - 2 * amount);
    }

    function testClaim_RevertWhen_InvalidProof() public {
        uint256 amount = 1e18;

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        leaf = keccak256(bytes.concat(keccak256(abi.encode(_user, amount))));
        vm.expectRevert(abi.encodeWithSelector(RewardsDistributor.InvalidProof.selector, proof, leaf));

        distributor.claim(proof, _user, amount);
    }

    function testClaim_RevertWhen_MaxLimitExceeded() public {
        distributor = new RewardsDistributor(kinto, engen, root, 0, startTime);
        uint256 amount = 1e18;

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = 0xb92c48e9d7abe27fd8dfd6b5dfdbfb1c9a463f80c712b66f3a5180a090cccafc;
        proof[1] = 0xfe69d275d3541c8c5338701e9b211e3fc949b5efb1d00a410313e7474952967f;

        vm.expectRevert(abi.encodeWithSelector(RewardsDistributor.MaxLimitReached.selector, amount, 0));
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

    function testUpdateRoot_RevertWhen_NotOwner() public {
        bytes32 newRoot = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
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

    function testUpdateBonusAmount_RevertWhen_NotOwner() public {
        uint256 newBonusAmount = 1_000_000e18;

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        distributor.updateBonusAmount(newBonusAmount);
    }

    function testClaimEngen() public {
        uint256 amount = 1e18;

        kinto.mint(address(distributor), amount);
        engen.mint(address(_user), amount);

        assertEq(kinto.balanceOf(address(distributor)), amount);
        assertEq(kinto.balanceOf(_user), 0);
        assertEq(engen.balanceOf(_user), amount);

        vm.prank(_user);
        emit RewardsDistributor.UserEngenClaimed(_user, amount);
        distributor.claimEngen();

        uint256 claimedEngenAmount = amount * 22e16 / 1e18;

        assertEq(kinto.balanceOf(address(distributor)), amount - claimedEngenAmount);
        assertEq(kinto.balanceOf(_user), claimedEngenAmount);
        assertEq(distributor.totalKintoFromEngenClaimed(), claimedEngenAmount);
    }

    function testUpdateEngenHolders() public {
        address[] memory users = new address[](2);
        bool[] memory values = new bool[](2);

        users[0] = address(0x123);
        users[1] = address(0x456);
        values[0] = true;
        values[1] = false;

        vm.prank(_owner);
        distributor.updateEngenHolders(users, values);

        assertEq(distributor.engenHolders(address(0x123)), true);
        assertEq(distributor.engenHolders(address(0x456)), false);
    }

    function testUpdateEngenHolders_RevertWhen_NotOwner() public {
        address[] memory users = new address[](2);
        bool[] memory values = new bool[](2);

        users[0] = address(0x123);
        users[1] = address(0x456);
        values[0] = true;
        values[1] = false;

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        distributor.updateEngenHolders(users, values);
    }
}

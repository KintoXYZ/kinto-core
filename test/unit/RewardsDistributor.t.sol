// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin-5.0.1/contracts/utils/cryptography/ECDSA.sol";

import {ForkTest} from "@kinto-core-test/helpers/ForkTest.sol";
import {ERC20Mock} from "@kinto-core-test/helpers/ERC20Mock.sol";

import {RewardsDistributor} from "@kinto-core/RewardsDistributor.sol";

contract RewardsDistributorTest is ForkTest {
    RewardsDistributor internal distributor;
    ERC20Mock internal kinto;
    bytes32 internal root = 0xf5d3a04b6083ba8077d903785b3001db5b9077f1a3af3e06d27a8a9fa3567546;
    bytes32 internal leaf;
    uint256 internal engenFunds = 600_000e18;
    uint256 internal maxRatePerSecond = 3e16; // 0.03 tokens per second, or 2,592 tokens per day
    uint256 internal startTime = 1;

    function setUp() public override {
        super.setUp();

        kinto = new ERC20Mock("Kinto Token", "KINTO", 18);

        distributor = new RewardsDistributor(kinto, root, _owner, _upgrader, engenFunds, maxRatePerSecond, startTime);
    }

    function testUp() public override {}

    function testClaim() public {
        uint256 amount = 1e18;

        kinto.mint(address(distributor), amount);

        assertEq(kinto.balanceOf(address(distributor)), amount);
        assertEq(kinto.balanceOf(_user), 0);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0xb92c48e9d7abe27fd8dfd6b5dfdbfb1c9a463f80c712b66f3a5180a090cccafc;

        distributor.claim(proof, _user, amount);

        assertEq(kinto.balanceOf(address(distributor)), 0);
        assertEq(kinto.balanceOf(_user), amount);
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
        distributor = new RewardsDistributor(kinto, root, _owner, _upgrader, 0, maxRatePerSecond, startTime); uint256 amount = 1e18;

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0xb92c48e9d7abe27fd8dfd6b5dfdbfb1c9a463f80c712b66f3a5180a090cccafc;
        vm.expectRevert(abi.encodeWithSelector(RewardsDistributor.MaxLimitReached.selector, amount, 0));
        distributor.claim(proof, _user, amount);
    }
}

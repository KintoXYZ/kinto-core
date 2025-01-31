// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {SealedBidTokenSale} from "@kinto-core/apps/SealedBidTokenSale.sol";
import {ERC20Mock} from "@kinto-core-test/helpers/ERC20Mock.sol";
import {MerkleProof} from "@openzeppelin-5.0.1/contracts/utils/cryptography/MerkleProof.sol";
import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";

contract SealedBidTokenSaleTest is SharedSetup {
    using MerkleProof for bytes32[];

    SealedBidTokenSale public sale;
    ERC20Mock public usdc;
    ERC20Mock public saleToken;

    uint256 public startTime;
    uint256 public endTime;
    uint256 public constant MIN_CAP = 10e6 * 1e6;
    uint256 public constant MAX_CAP = 20e6 * 1e6;

    bytes32 public merkleRoot;
    bytes32[] public proof;
    uint256 public allocation = 500 ether;

    function setUp() public override {
        super.setUp();

        startTime = block.timestamp + 1 days;
        endTime = startTime + 4 days;

        // Deploy mock tokens
        usdc = new ERC20Mock("USDC", "USDC", 6);
        saleToken = new ERC20Mock("K", "KINTO", 18);

        // Deploy sale contract with admin as owner
        vm.prank(admin);
        sale = new SealedBidTokenSale(address(saleToken), TREASURY, address(usdc), startTime, endTime, MIN_CAP, MAX_CAP);

        // Setup Merkle tree with alice and bob
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = keccak256(abi.encodePacked(alice, allocation));
        leaves[1] = keccak256(abi.encodePacked(bob, allocation * 2));
        merkleRoot = buildRoot(leaves);
        proof = getProof(leaves, 0);
    }

    // Helper to build Merkle root
    function buildRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        bytes32[] memory nodes = leaves;
        uint256 n = leaves.length;
        while (n > 1) {
            for (uint256 i = 0; i < n; i += 2) {
                nodes[i / 2] = keccak256(abi.encodePacked(nodes[i], nodes[i + 1]));
            }
            n = (n + 1) / 2;
        }
        return nodes[0];
    }

    // Helper to get proof for a leaf
    function getProof(bytes32[] memory leaves, uint256 index) internal pure returns (bytes32[] memory) {
        bytes32[] memory proof = new bytes32[](leaves.length);
        uint256 level = 0;
        uint256 n = leaves.length;

        while (n > 1) {
            if (index % 2 == 1) {
                proof[level] = leaves[index - 1];
            } else if (index + 1 < n) {
                proof[level] = leaves[index + 1];
            }
            index /= 2;
            n = (n + 1) / 2;
            level++;
        }
        return proof;
    }

    /* ============ Constructor Tests ============ */
    function testConstructor() public {
        assertEq(address(sale.saleToken()), address(saleToken));
        assertEq(address(sale.USDC()), address(usdc));
        assertEq(sale.treasury(), TREASURY);
        assertEq(sale.startTime(), startTime);
        assertEq(sale.endTime(), endTime);
        assertEq(sale.minimumCap(), MIN_CAP);
        assertEq(sale.maximumCap(), MAX_CAP);
        assertEq(sale.owner(), admin);
    }

    /* ============ Deposit Tests ============ */
    function testDeposit() public {
        vm.warp(startTime + 1);
        uint256 amount = 1000 * 1e6;

        // Mint and approve USDC
        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        // Deposit through Kinto Wallet
        vm.prank(alice);
        sale.deposit(amount);

        assertEq(sale.deposits(alice), amount);
        assertEq(sale.totalDeposited(), amount);
        assertEq(usdc.balanceOf(address(sale)), amount);
    }

    function testDeposit_RevertWhen_BeforeStart() public {
        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.SaleNotStarted.selector, block.timestamp, startTime));
        vm.prank(alice);
        sale.deposit(100 ether);
    }

    /* ============ Finalize Tests ============ */
    function testFinalize_Success() public {
        vm.warp(startTime + 1);

        usdc.mint(alice, MAX_CAP);

        vm.prank(alice);
        usdc.approve(address(sale), MAX_CAP);

        vm.prank(alice);
        sale.deposit(MAX_CAP);

        vm.warp(endTime);
        vm.prank(admin);
        sale.finalize();

        assertTrue(sale.finalized());
        assertTrue(sale.successful());
    }

    /* ============ Withdraw Tests ============ */
    function testWithdraw() public {
        uint256 amount = 1000 * 1e6;

        // Setup failed sale
        vm.warp(startTime + 1);

        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        vm.prank(alice);
        sale.deposit(amount);

        vm.warp(endTime);
        vm.prank(admin);
        sale.finalize();

        vm.prank(alice);
        sale.withdraw();

        assertEq(sale.deposits(alice), 0);
        assertEq(usdc.balanceOf(alice), amount);
    }

    /* ============ Claim Tests ============ */
    function testClaimTokens() public {
        vm.warp(startTime + 1);

        usdc.mint(alice, MAX_CAP);

        vm.prank(alice);
        usdc.approve(address(sale), MAX_CAP);

        vm.prank(alice);
        sale.deposit(MAX_CAP);

        vm.warp(endTime);
        vm.prank(admin);
        sale.finalize();

        vm.prank(admin);
        sale.setMerkleRoot(merkleRoot);

        vm.prank(alice);
        sale.claimTokens(allocation, proof);

        assertTrue(sale.hasClaimed(alice));
        assertEq(saleToken.balanceOf(alice), allocation);
    }

    /* ============ Admin Function Tests ============ */

    function testWithdrawProceeds() public {
        vm.warp(startTime + 1);

        usdc.mint(alice, MAX_CAP);

        vm.prank(alice);
        usdc.approve(address(sale), MAX_CAP);

        vm.prank(alice);
        sale.deposit(MAX_CAP);

        vm.warp(endTime);
        vm.prank(admin);
        sale.finalize();

        vm.prank(admin);
        sale.withdrawProceeds();

        assertEq(usdc.balanceOf(TREASURY), MAX_CAP);
    }
}

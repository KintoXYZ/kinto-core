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
    uint256 public saleTokenAllocation = 1000 * 1e18;
    uint256 public usdcAllocation = 1000 * 1e6;

    function setUp() public override {
        super.setUp();

        startTime = block.timestamp + 1 days;
        endTime = startTime + 4 days;

        // Deploy mock tokens
        usdc = new ERC20Mock("USDC", "USDC", 6);
        saleToken = new ERC20Mock("K", "KINTO", 18);

        // Deploy sale contract with admin as owner
        vm.prank(admin);
        sale = new SealedBidTokenSale(address(saleToken), TREASURY, address(usdc), startTime, MIN_CAP);

        // Setup Merkle tree with alice and bob
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = keccak256(abi.encodePacked(alice, saleTokenAllocation, usdcAllocation));
        leaves[1] = keccak256(abi.encodePacked(bob, saleTokenAllocation * 2, usdcAllocation));

        merkleRoot = buildRoot(leaves);
        proof = buildProof(leaves, 0);
    }

    // Following code is adapted from https://github.com/dmfxyz/murky/blob/main/src/common/MurkyBase.sol.
    function buildRoot(bytes32[] memory leaves) private pure returns (bytes32) {
        require(leaves.length > 1);
        while (leaves.length > 1) {
            leaves = hashLevel(leaves);
        }
        return leaves[0];
    }

    function buildProof(bytes32[] memory leaves, uint256 nodeIndex) private pure returns (bytes32[] memory) {
        require(leaves.length > 1);

        bytes32[] memory result = new bytes32[](64);
        uint256 pos;

        while (leaves.length > 1) {
            unchecked {
                if (nodeIndex & 0x1 == 1) {
                    result[pos] = leaves[nodeIndex - 1];
                } else if (nodeIndex + 1 == leaves.length) {
                    result[pos] = bytes32(0);
                } else {
                    result[pos] = leaves[nodeIndex + 1];
                }
                ++pos;
                nodeIndex /= 2;
            }
            leaves = hashLevel(leaves);
        }
        // Resize the length of the array to fit.
        /// @solidity memory-safe-assembly
        assembly {
            mstore(result, pos)
        }

        return result;
    }

    function hashLevel(bytes32[] memory leaves) private pure returns (bytes32[] memory) {
        bytes32[] memory result;
        unchecked {
            uint256 length = leaves.length;
            if (length & 0x1 == 1) {
                result = new bytes32[](length / 2 + 1);
                result[result.length - 1] = hashPair(leaves[length - 1], bytes32(0));
            } else {
                result = new bytes32[](length / 2);
            }
            uint256 pos = 0;
            for (uint256 i = 0; i < length - 1; i += 2) {
                result[pos] = hashPair(leaves[i], leaves[i + 1]);
                ++pos;
            }
        }
        return result;
    }

    function hashPair(bytes32 left, bytes32 right) private pure returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            switch lt(left, right)
            case 0 {
                mstore(0x0, right)
                mstore(0x20, left)
            }
            default {
                mstore(0x0, left)
                mstore(0x20, right)
            }
            result := keccak256(0x0, 0x40)
        }
    }

    /* ============ Constructor Tests ============ */

    function testConstructor() public view {
        assertEq(address(sale.saleToken()), address(saleToken));
        assertEq(address(sale.USDC()), address(usdc));
        assertEq(sale.treasury(), TREASURY);
        assertEq(sale.startTime(), startTime);
        assertEq(sale.minimumCap(), MIN_CAP);
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

    /* ============ endSale ============ */

    function testEndSale() public {
        vm.warp(startTime + 1);

        usdc.mint(alice, MAX_CAP);

        vm.prank(alice);
        usdc.approve(address(sale), MAX_CAP);

        vm.prank(alice);
        sale.deposit(MAX_CAP);

        vm.prank(admin);
        sale.endSale();

        assertTrue(sale.saleEnded());
        assertTrue(sale.successful());
    }

    /* ============ Withdraw ============ */

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
        sale.endSale();

        vm.prank(alice);
        sale.withdraw();

        assertEq(sale.deposits(alice), 0);
        assertEq(usdc.balanceOf(alice), amount);
    }

    /* ============ claimTokens ============ */

    function testClaimTokens() public {
        vm.warp(startTime + 1);

        usdc.mint(alice, MAX_CAP);
        saleToken.mint(address(sale), saleTokenAllocation);

        vm.prank(alice);
        usdc.approve(address(sale), MAX_CAP);

        vm.prank(alice);
        sale.deposit(MAX_CAP);

        vm.warp(endTime);
        vm.prank(admin);
        sale.endSale();

        vm.prank(admin);
        sale.setMerkleRoot(merkleRoot);

        vm.prank(alice);
        sale.claimTokens(saleTokenAllocation, usdcAllocation, proof);

        assertTrue(sale.hasClaimed(alice));
        assertEq(saleToken.balanceOf(alice), saleTokenAllocation);
        assertEq(usdc.balanceOf(alice), usdcAllocation);
        assertEq(saleToken.balanceOf(address(sale)), 0);
    }

    /* ============ withdrawProceeds ============ */

    function testWithdrawProceeds() public {
        vm.warp(startTime + 1);

        usdc.mint(alice, MAX_CAP);

        vm.prank(alice);
        usdc.approve(address(sale), MAX_CAP);

        vm.prank(alice);
        sale.deposit(MAX_CAP);

        vm.warp(endTime);
        vm.prank(admin);
        sale.endSale();

        vm.prank(admin);
        sale.withdrawProceeds();

        assertEq(usdc.balanceOf(TREASURY), MAX_CAP);
    }
}

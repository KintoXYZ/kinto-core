// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
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

    uint256 public preStartTime;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public constant MIN_CAP = 10e6 * 1e6;
    uint256 public constant MAX_CAP = 20e6 * 1e6;

    bytes32 public merkleRoot;
    bytes32[] public proof;
    uint256 public saleTokenAllocation = 1000 * 1e18;
    uint256 public usdcAllocation = 1000 * 1e6;
    uint256 public maxPrice = 10 * 1e6;

    function setUp() public override {
        super.setUp();

        preStartTime = block.timestamp + 1 days;
        startTime = block.timestamp + 2 days;
        endTime = startTime + 4 days;

        // Deploy mock tokens
        usdc = new ERC20Mock("USDC", "USDC", 6);
        saleToken = new ERC20Mock("K", "KINTO", 18);

        sale = new SealedBidTokenSale(address(saleToken), TREASURY, address(usdc), preStartTime, startTime, MIN_CAP);
        vm.startPrank(admin);
        sale = SealedBidTokenSale(address(new UUPSProxy{salt: 0}(address(sale), "")));
        sale.initialize();
        vm.stopPrank();

        // Setup Merkle tree with alice and bob
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = keccak256(bytes.concat(keccak256(abi.encode(alice, saleTokenAllocation, usdcAllocation))));
        leaves[1] = keccak256(bytes.concat(keccak256(abi.encode(bob, saleTokenAllocation * 2, usdcAllocation))));

        merkleRoot = buildRoot(leaves);
        proof = buildProof(leaves, 0);
    }

    // Following code is adapted from https://github.com/dmfxyz/murky/blob/main/src/common/MurkyBase.sol.
    function buildRoot(bytes32[] memory leaves) private pure returns (bytes32) {
        require(leaves.length > 1, "leaves.length > 1");
        while (leaves.length > 1) {
            leaves = hashLevel(leaves);
        }
        return leaves[0];
    }

    function buildProof(bytes32[] memory leaves, uint256 nodeIndex) private pure returns (bytes32[] memory) {
        require(leaves.length > 1, "leaves.length > 1");

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

    /* ============ Constructor ============ */

    function testConstructor() public view {
        assertEq(address(sale.saleToken()), address(saleToken));
        assertEq(address(sale.USDC()), address(usdc));
        assertEq(sale.treasury(), TREASURY);
        assertEq(sale.startTime(), startTime);
        assertEq(sale.minimumCap(), MIN_CAP);
        assertEq(sale.owner(), admin);
    }

    /* ============ Deposit ============ */

    function testDeposit() public {
        vm.warp(startTime + 1);
        uint256 amount = 1000 * 1e6;

        // Mint and approve USDC
        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        // Deposit with maxPrice
        vm.prank(alice);
        sale.deposit(amount, maxPrice);

        assertEq(sale.deposits(alice), amount);
        assertEq(sale.totalDeposited(), amount);
        assertEq(usdc.balanceOf(address(sale)), amount);
        assertEq(sale.maxPrices(alice), maxPrice);
    }

    function testDeposit_RevertWhen_BeforeStart() public {
        vm.expectRevert(
            abi.encodeWithSelector(SealedBidTokenSale.SaleNotStarted.selector, block.timestamp, preStartTime)
        );
        vm.prank(alice);
        sale.deposit(100 ether, maxPrice);
    }

    function testDeposit_RevertWhen_SaleEnded() public {
        // Advance time to start of sale
        vm.warp(startTime + 1);

        // End the sale
        vm.prank(admin);
        sale.endSale();

        // Try to deposit after sale has ended
        uint256 amount = 1000 * 1e6;
        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.SaleAlreadyEnded.selector, block.timestamp));
        sale.deposit(amount, maxPrice);
    }

    function testDeposit_RevertWhen_MinAmount() public {
        // Advance time to start of sale
        vm.warp(startTime + 1);

        // Try to deposit zero amount
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.MinDeposit.selector, 250 * 1e6 - 1));
        sale.deposit(250 * 1e6 - 1, maxPrice);
    }

    function testDeposit_MultipleDeposits() public {
        // Advance time to start of sale
        vm.warp(startTime + 1);

        uint256 firstAmount = 250 * 1e6;
        uint256 secondAmount = 2000 * 1e6;
        uint256 totalAmount = firstAmount + secondAmount;

        // Mint and approve USDC for both deposits
        usdc.mint(alice, totalAmount);
        vm.prank(alice);
        usdc.approve(address(sale), totalAmount);

        // Make first deposit
        vm.prank(alice);
        sale.deposit(firstAmount, maxPrice);

        // Make second deposit
        vm.prank(alice);
        sale.deposit(secondAmount, maxPrice * 2);

        // Verify final state
        assertEq(sale.deposits(alice), totalAmount);
        assertEq(sale.totalDeposited(), totalAmount);
        assertEq(usdc.balanceOf(address(sale)), totalAmount);
        assertEq(sale.maxPrices(alice), maxPrice * 2);
    }

    function testDeposit_MultipleUsers() public {
        // Advance time to start of sale
        vm.warp(startTime + 1);

        uint256 aliceAmount = 1000 * 1e6;
        uint256 bobAmount = 2000 * 1e6;
        uint256 totalAmount = aliceAmount + bobAmount;

        // Setup Alice's deposit
        usdc.mint(alice, aliceAmount);
        vm.prank(alice);
        usdc.approve(address(sale), aliceAmount);

        // Setup Bob's deposit
        usdc.mint(bob, bobAmount);
        vm.prank(bob);
        usdc.approve(address(sale), bobAmount);

        // Make deposits
        vm.prank(alice);
        sale.deposit(aliceAmount, maxPrice * 2);

        vm.prank(bob);
        sale.deposit(bobAmount, maxPrice);

        // Verify final state
        assertEq(sale.deposits(alice), aliceAmount);
        assertEq(sale.deposits(bob), bobAmount);
        assertEq(sale.maxPrices(alice), maxPrice * 2);
        assertEq(sale.totalDeposited(), totalAmount);
        assertEq(usdc.balanceOf(address(sale)), totalAmount);
        assertEq(sale.maxPrices(bob), maxPrice);
        assertEq(sale.maxPrices(alice), maxPrice * 2);
    }

    /* ============ endSale ============ */

    function testEndSale() public {
        vm.warp(startTime + 1);

        usdc.mint(alice, MAX_CAP);

        vm.prank(alice);
        usdc.approve(address(sale), MAX_CAP);

        vm.prank(alice);
        sale.deposit(MAX_CAP, maxPrice);

        vm.prank(admin);
        sale.endSale();

        assertTrue(sale.saleEnded());
        assertTrue(sale.capReached());
    }

    function testEndSale_WhenCapNotReached() public {
        // Setup sale with amount below minimum cap
        vm.warp(startTime + 1);
        uint256 amount = MIN_CAP - 1e6; // Just under minimum cap

        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        vm.prank(alice);
        sale.deposit(amount, maxPrice);

        // End sale
        vm.prank(admin);
        sale.endSale();

        assertTrue(sale.saleEnded());
        assertFalse(sale.capReached());
        assertEq(sale.totalDeposited(), amount);
    }

    function testEndSale_ExactlyAtMinCap() public {
        // Setup sale with amount exactly at minimum cap
        vm.warp(startTime + 1);
        uint256 amount = MIN_CAP;

        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        vm.prank(alice);
        sale.deposit(amount, maxPrice);

        // End sale
        vm.prank(admin);
        sale.endSale();

        assertTrue(sale.saleEnded());
        assertTrue(sale.capReached());
        assertEq(sale.totalDeposited(), amount);
    }

    function testEndSale_RevertWhen_NotOwner() public {
        vm.warp(startTime + 1);

        vm.prank(alice); // Non-owner tries to end sale
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        sale.endSale();
    }

    function testEndSale_RevertWhen_AlreadyEnded() public {
        vm.warp(startTime + 1);

        // First end sale
        vm.prank(admin);
        sale.endSale();

        // Try to end sale again
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.SaleAlreadyEnded.selector, block.timestamp));
        sale.endSale();
    }

    function testEndSale_WithNoDeposits() public {
        vm.warp(startTime + 1);

        // End sale with no deposits
        vm.prank(admin);
        sale.endSale();

        assertTrue(sale.saleEnded());
        assertFalse(sale.capReached());
        assertEq(sale.totalDeposited(), 0);
    }

    function testEndSale_WithMultipleDeposits() public {
        vm.warp(startTime + 1);

        // Setup multiple deposits that sum to above minimum cap
        uint256 aliceAmount = MIN_CAP / 2;
        uint256 bobAmount = MIN_CAP / 2 + 1e6; // Slightly more to go over MIN_CAP

        // Alice's deposit
        usdc.mint(alice, aliceAmount);
        vm.prank(alice);
        usdc.approve(address(sale), aliceAmount);

        vm.prank(alice);
        sale.deposit(aliceAmount, maxPrice);

        // Bob's deposit
        usdc.mint(bob, bobAmount);
        vm.prank(bob);
        usdc.approve(address(sale), bobAmount);

        vm.prank(bob);
        sale.deposit(bobAmount, maxPrice);

        // End sale
        vm.prank(admin);
        sale.endSale();

        assertTrue(sale.saleEnded());
        assertTrue(sale.capReached());
        assertEq(sale.totalDeposited(), aliceAmount + bobAmount);
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
        sale.deposit(amount, maxPrice);

        vm.warp(endTime);
        vm.prank(admin);
        sale.endSale();

        vm.prank(alice);
        sale.withdraw();

        assertEq(sale.deposits(alice), 0);
        assertEq(usdc.balanceOf(alice), amount);
    }

    function testWithdraw_RevertWhen_SaleNotEnded() public {
        // Setup deposit
        vm.warp(startTime + 1);

        uint256 amount = 1000 * 1e6;
        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        vm.prank(alice);
        sale.deposit(amount, maxPrice);

        // Attempt withdrawal before sale ends
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.SaleNotEnded.selector, block.timestamp));
        sale.withdraw();
    }

    function testWithdraw_RevertWhen_CapReached() public {
        // Setup successful sale
        vm.warp(startTime + 1);

        uint256 amount = MIN_CAP; // Use minimum cap to ensure success
        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        vm.prank(alice);
        sale.deposit(amount, maxPrice);

        // End sale successfully
        vm.prank(admin);
        sale.endSale();

        // Attempt withdrawal on successful sale
        vm.prank(alice);
        vm.expectRevert(SealedBidTokenSale.CapReached.selector);
        sale.withdraw();
    }

    function testWithdraw_RevertWhen_NoDeposit() public {
        vm.warp(startTime + 1);

        vm.prank(admin);
        sale.endSale();

        // Attempt withdrawal with no deposit
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.NothingToWithdraw.selector, alice));
        sale.withdraw();
    }

    function testWithdraw_MultipleUsers() public {
        // Setup deposits for multiple users
        vm.warp(startTime + 1);
        uint256 aliceAmount = 1000 * 1e6;
        uint256 bobAmount = 2000 * 1e6;

        // Setup and execute Alice's deposit
        usdc.mint(alice, aliceAmount);
        vm.prank(alice);
        usdc.approve(address(sale), aliceAmount);

        vm.prank(alice);
        sale.deposit(aliceAmount, maxPrice);

        // Setup and execute Bob's deposit
        usdc.mint(bob, bobAmount);
        vm.prank(bob);
        usdc.approve(address(sale), bobAmount);

        vm.prank(bob);
        sale.deposit(bobAmount, maxPrice);

        // End sale as failed
        vm.warp(endTime);
        vm.prank(admin);
        sale.endSale();

        // Execute withdrawals
        vm.prank(alice);
        sale.withdraw();

        vm.prank(bob);
        sale.withdraw();

        // Verify final states
        assertEq(sale.deposits(alice), 0);
        assertEq(sale.deposits(bob), 0);
        assertEq(usdc.balanceOf(alice), aliceAmount);
        assertEq(usdc.balanceOf(bob), bobAmount);
        assertEq(usdc.balanceOf(address(sale)), 0);
    }

    function testWithdraw_RevertWhen_DoubleWithdraw() public {
        // Setup deposit
        vm.warp(startTime + 1);

        uint256 amount = 1000 * 1e6;
        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        vm.prank(alice);
        sale.deposit(amount, maxPrice);

        // End sale as failed
        vm.warp(endTime);
        vm.prank(admin);
        sale.endSale();

        // First withdrawal (should succeed)
        vm.prank(alice);
        sale.withdraw();

        // Second withdrawal attempt (should fail)
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.NothingToWithdraw.selector, alice));
        sale.withdraw();

        // Verify final state
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
        sale.deposit(MAX_CAP, maxPrice);

        vm.warp(endTime);
        vm.prank(admin);
        sale.endSale();

        vm.prank(admin);
        sale.setMerkleRoot(merkleRoot);

        sale.claimTokens(saleTokenAllocation, usdcAllocation, proof, alice);

        assertTrue(sale.hasClaimed(alice));
        assertEq(saleToken.balanceOf(alice), saleTokenAllocation);
        assertEq(usdc.balanceOf(alice), usdcAllocation);
        assertEq(saleToken.balanceOf(address(sale)), 0);
    }

    function testClaimTokens_RevertWhen_SaleNotEnded() public {
        // Sale not ended yet
        vm.warp(startTime + 1);

        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.CapNotReached.selector));
        sale.claimTokens(saleTokenAllocation, usdcAllocation, proof, alice);
    }

    function testClaimTokens_RevertWhen_SaleNotSuccessful() public {
        // Setup failed sale (deposit less than min cap)
        vm.warp(startTime + 1);
        uint256 amount = MIN_CAP - 1e6; // Just under minimum cap

        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        vm.prank(alice);
        sale.deposit(amount, maxPrice);

        // End sale (will fail due to not meeting min cap)
        vm.warp(endTime);
        vm.prank(admin);
        sale.endSale();

        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.CapNotReached.selector));
        sale.claimTokens(saleTokenAllocation, usdcAllocation, proof, alice);
    }

    function testClaimTokens_RevertWhen_MerkleRootNotSet() public {
        // Setup successful sale
        vm.warp(startTime + 1);

        usdc.mint(alice, MAX_CAP);
        vm.prank(alice);
        usdc.approve(address(sale), MAX_CAP);

        vm.prank(alice);
        sale.deposit(MAX_CAP, maxPrice);

        vm.prank(admin);
        sale.endSale();

        // Attempt claim before merkle root is set
        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.MerkleRootNotSet.selector));
        sale.claimTokens(saleTokenAllocation, usdcAllocation, proof, alice);
    }

    function testClaimTokens_RevertWhen_InvalidProof() public {
        // Setup successful sale
        vm.warp(startTime + 1);

        usdc.mint(alice, MAX_CAP);
        saleToken.mint(address(sale), saleTokenAllocation);

        vm.prank(alice);
        usdc.approve(address(sale), MAX_CAP);

        vm.prank(alice);
        sale.deposit(MAX_CAP, maxPrice);

        vm.warp(endTime);
        vm.prank(admin);
        sale.endSale();

        vm.prank(admin);
        sale.setMerkleRoot(merkleRoot);

        // Create invalid proof by using bob's proof for alice
        bytes32[] memory invalidProof = buildProof(
            new bytes32[](2), // Empty leaves will create invalid proof
            0
        );

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(alice, saleTokenAllocation, usdcAllocation))));

        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.InvalidProof.selector, invalidProof, leaf));
        sale.claimTokens(saleTokenAllocation, usdcAllocation, invalidProof, alice);
    }

    function testClaimTokens_RevertWhen_AlreadyClaimed() public {
        // Setup successful sale
        vm.warp(startTime + 1);

        usdc.mint(alice, MAX_CAP);
        saleToken.mint(address(sale), saleTokenAllocation);

        vm.prank(alice);
        usdc.approve(address(sale), MAX_CAP);

        vm.prank(alice);
        sale.deposit(MAX_CAP, maxPrice);

        vm.warp(endTime);
        vm.prank(admin);
        sale.endSale();

        vm.prank(admin);
        sale.setMerkleRoot(merkleRoot);

        // First claim (should succeed)
        sale.claimTokens(saleTokenAllocation, usdcAllocation, proof, alice);

        // Second claim attempt (should fail)
        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.AlreadyClaimed.selector, alice));
        sale.claimTokens(saleTokenAllocation, usdcAllocation, proof, alice);
    }

    function testClaimTokens_WhenZeroTokenAllocation() public {
        // Setup successful sale
        vm.warp(startTime + 1);

        usdc.mint(alice, MAX_CAP);
        usdc.mint(address(sale), usdcAllocation);

        vm.prank(alice);
        usdc.approve(address(sale), MAX_CAP);

        vm.prank(alice);
        sale.deposit(MAX_CAP, maxPrice);

        vm.warp(endTime);
        vm.prank(admin);
        sale.endSale();

        // Create merkle tree with zero token allocation
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = keccak256(bytes.concat(keccak256(abi.encode(alice, 0, usdcAllocation))));
        leaves[1] = keccak256(bytes.concat(keccak256(abi.encode(bob, 0, 0))));

        bytes32 newRoot = buildRoot(leaves);
        bytes32[] memory zeroTokenProof = buildProof(leaves, 0);

        vm.prank(admin);
        sale.setMerkleRoot(newRoot);

        // Claim with zero token allocation
        uint256 initialBalance = saleToken.balanceOf(alice);
        sale.claimTokens(0, usdcAllocation, zeroTokenProof, alice);

        // Verify only USDC was transferred
        assertEq(saleToken.balanceOf(alice), initialBalance);
        assertEq(usdc.balanceOf(alice), usdcAllocation);
        assertTrue(sale.hasClaimed(alice));
    }

    function testClaimTokens_WhenZeroUSDCAllocation() public {
        // Setup successful sale
        vm.warp(startTime + 1);

        usdc.mint(alice, MAX_CAP);
        saleToken.mint(address(sale), saleTokenAllocation);

        vm.prank(alice);
        usdc.approve(address(sale), MAX_CAP);
        vm.prank(alice);
        sale.deposit(MAX_CAP, maxPrice);

        vm.warp(endTime);
        vm.prank(admin);
        sale.endSale();

        // Create merkle tree with zero USDC allocation
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = keccak256(bytes.concat(keccak256(abi.encode(alice, saleTokenAllocation, 0))));
        leaves[1] = keccak256(bytes.concat(keccak256(abi.encode(bob, 0, 0))));

        bytes32 newRoot = buildRoot(leaves);
        bytes32[] memory zeroUsdcProof = buildProof(leaves, 0);

        vm.prank(admin);
        sale.setMerkleRoot(newRoot);

        // Claim with zero USDC allocation
        uint256 initialUsdcBalance = usdc.balanceOf(alice);
        sale.claimTokens(saleTokenAllocation, 0, zeroUsdcProof, alice);

        // Verify only tokens were transferred
        assertEq(saleToken.balanceOf(alice), saleTokenAllocation);
        assertEq(usdc.balanceOf(alice), initialUsdcBalance);
        assertTrue(sale.hasClaimed(alice));
    }

    /* ============ setMerkleRoot ============ */

    function testSetMerkleRoot() public {
        // Setup successful sale first
        vm.warp(startTime + 1);

        usdc.mint(alice, MIN_CAP);
        vm.prank(alice);
        usdc.approve(address(sale), MIN_CAP);

        vm.prank(alice);
        sale.deposit(MIN_CAP, maxPrice);

        vm.prank(admin);
        sale.endSale();

        // Set merkle root
        bytes32 newRoot = keccak256("newRoot");
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit SealedBidTokenSale.MerkleRootSet(newRoot);
        sale.setMerkleRoot(newRoot);

        assertEq(sale.merkleRoot(), newRoot);
    }

    function testSetMerkleRoot_RevertWhen_SaleNotEnded() public {
        // Try to set merkle root before sale ends
        vm.warp(startTime + 1);

        bytes32 newRoot = keccak256("newRoot");
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.CapNotReached.selector));
        sale.setMerkleRoot(newRoot);
    }

    function testSetMerkleRoot_RevertWhen_CapNotReached() public {
        // Setup failed sale (below MIN_CAP)
        vm.warp(startTime + 1);

        uint256 amount = MIN_CAP - 1e6; // Just below minimum cap
        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        vm.prank(alice);
        sale.deposit(amount, maxPrice);

        vm.prank(admin);
        sale.endSale();

        // Try to set merkle root
        bytes32 newRoot = keccak256("newRoot");
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.CapNotReached.selector));
        sale.setMerkleRoot(newRoot);
    }

    function testSetMerkleRoot_RevertWhen_NotOwner() public {
        // Setup successful sale
        vm.warp(startTime + 1);

        usdc.mint(alice, MIN_CAP);
        vm.prank(alice);
        usdc.approve(address(sale), MIN_CAP);
        vm.prank(alice);
        sale.deposit(MIN_CAP, maxPrice);

        vm.prank(admin);
        sale.endSale();

        // Try to set merkle root from non-owner
        bytes32 newRoot = keccak256("newRoot");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        sale.setMerkleRoot(newRoot);
    }

    function testSetMerkleRoot_UpdateExisting() public {
        // Setup successful sale
        vm.warp(startTime + 1);

        usdc.mint(alice, MIN_CAP);
        vm.prank(alice);
        usdc.approve(address(sale), MIN_CAP);

        vm.prank(alice);
        sale.deposit(MIN_CAP, maxPrice);

        vm.prank(admin);
        sale.endSale();

        // Set initial root
        bytes32 initialRoot = keccak256("initialRoot");
        vm.prank(admin);
        sale.setMerkleRoot(initialRoot);
        assertEq(sale.merkleRoot(), initialRoot);

        // Update to new root
        bytes32 newRoot = keccak256("newRoot");
        vm.prank(admin);
        sale.setMerkleRoot(newRoot);
        assertEq(sale.merkleRoot(), newRoot);
    }

    function testSetMerkleRoot_ZeroRoot() public {
        // Setup successful sale
        vm.warp(startTime + 1);

        usdc.mint(alice, MIN_CAP);
        vm.prank(alice);
        usdc.approve(address(sale), MIN_CAP);
        vm.prank(alice);
        sale.deposit(MIN_CAP, maxPrice);

        vm.prank(admin);
        sale.endSale();

        // Set zero merkle root
        bytes32 zeroRoot = bytes32(0);
        vm.prank(admin);
        sale.setMerkleRoot(zeroRoot);
        assertEq(sale.merkleRoot(), zeroRoot);
    }

    /* ============ withdrawProceeds ============ */

    function testWithdrawProceeds() public {
        // Setup successful sale
        vm.warp(startTime + 1);

        uint256 depositAmount = MIN_CAP;
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        usdc.approve(address(sale), depositAmount);

        vm.prank(alice);
        sale.deposit(depositAmount, maxPrice);

        vm.prank(admin);
        sale.endSale();

        // Check initial balances
        uint256 initialTreasuryBalance = usdc.balanceOf(TREASURY);
        usdc.balanceOf(address(sale));

        // Withdraw proceeds
        vm.prank(admin);
        sale.withdrawProceeds();

        // Verify balances after withdrawal
        assertEq(usdc.balanceOf(TREASURY), initialTreasuryBalance + depositAmount);
        assertEq(usdc.balanceOf(address(sale)), 0);
    }

    function testWithdrawProceeds_RevertWhen_SaleNotEnded() public {
        // Setup sale but don't end it
        vm.warp(startTime + 1);

        uint256 depositAmount = MIN_CAP;
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        usdc.approve(address(sale), depositAmount);

        vm.prank(alice);
        sale.deposit(depositAmount, maxPrice);

        // Try to withdraw before ending sale
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.CapNotReached.selector));
        sale.withdrawProceeds();
    }

    function testWithdrawProceeds_RevertWhen_CapNotReached() public {
        // Setup failed sale
        vm.warp(startTime + 1);

        uint256 depositAmount = MIN_CAP - 1e6; // Just under minimum cap
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        usdc.approve(address(sale), depositAmount);
        vm.prank(alice);
        sale.deposit(depositAmount, maxPrice);

        vm.prank(admin);
        sale.endSale();

        // Try to withdraw when cap not reached
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.CapNotReached.selector));
        sale.withdrawProceeds();
    }

    function testWithdrawProceeds_RevertWhen_NotOwner() public {
        // Setup successful sale
        vm.warp(startTime + 1);

        uint256 depositAmount = MIN_CAP;
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        usdc.approve(address(sale), depositAmount);
        vm.prank(alice);
        sale.deposit(depositAmount, maxPrice);

        vm.prank(admin);
        sale.endSale();

        // Try to withdraw from non-owner account
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        sale.withdrawProceeds();
    }

    function testWithdrawProceeds_MultipleDeposits() public {
        // Setup successful sale with multiple deposits
        vm.warp(startTime + 1);

        uint256 aliceAmount = MIN_CAP / 2;
        uint256 bobAmount = MIN_CAP / 2 + 1e6; // Slightly more to go over MIN_CAP
        uint256 totalAmount = aliceAmount + bobAmount;

        // Alice's deposit
        usdc.mint(alice, aliceAmount);
        vm.prank(alice);
        usdc.approve(address(sale), aliceAmount);
        vm.prank(alice);
        sale.deposit(aliceAmount, maxPrice);

        // Bob's deposit
        usdc.mint(bob, bobAmount);
        vm.prank(bob);
        usdc.approve(address(sale), bobAmount);
        vm.prank(bob);
        sale.deposit(bobAmount, maxPrice);

        vm.prank(admin);
        sale.endSale();

        // Check initial balances
        uint256 initialTreasuryBalance = usdc.balanceOf(TREASURY);

        // Withdraw proceeds
        vm.prank(admin);
        sale.withdrawProceeds();

        // Verify full amount was transferred
        assertEq(usdc.balanceOf(TREASURY), initialTreasuryBalance + totalAmount);
        assertEq(usdc.balanceOf(address(sale)), 0);
    }

    function testWithdrawProceeds_MultipleTimes() public {
        // Setup successful sale
        vm.warp(startTime + 1);

        uint256 depositAmount = MIN_CAP;
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        usdc.approve(address(sale), depositAmount);
        vm.prank(alice);
        sale.deposit(depositAmount, maxPrice);

        vm.prank(admin);
        sale.endSale();

        // First withdrawal
        vm.prank(admin);
        sale.withdrawProceeds();
        assertEq(usdc.balanceOf(TREASURY), depositAmount);
        assertEq(usdc.balanceOf(address(sale)), 0);

        // Second withdrawal (should succeed but transfer 0)
        vm.prank(admin);
        sale.withdrawProceeds();
        assertEq(usdc.balanceOf(TREASURY), depositAmount); // Balance unchanged
        assertEq(usdc.balanceOf(address(sale)), 0);
    }

    function testWithdrawProceeds_ExactlyAtMinCap() public {
        // Setup successful sale exactly at minimum cap
        vm.warp(startTime + 1);

        uint256 depositAmount = MIN_CAP;
        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        usdc.approve(address(sale), depositAmount);
        vm.prank(alice);
        sale.deposit(depositAmount, maxPrice);

        vm.prank(admin);
        sale.endSale();

        uint256 initialTreasuryBalance = usdc.balanceOf(TREASURY);

        // Withdraw proceeds
        vm.prank(admin);
        sale.withdrawProceeds();

        assertEq(usdc.balanceOf(TREASURY), initialTreasuryBalance + depositAmount);
        assertEq(usdc.balanceOf(address(sale)), 0);
    }

    /* ============ updateMaxPrice ============ */

    function testUpdateMaxPrice_Timing() public {
        // Should fail before sale starts
        vm.expectRevert(
            abi.encodeWithSelector(SealedBidTokenSale.SaleNotStarted.selector, block.timestamp, preStartTime)
        );
        vm.prank(alice);
        sale.updateMaxPrice(1e6);

        // Should work during sale
        vm.warp(startTime + 1);
        vm.prank(alice);
        sale.updateMaxPrice(10e6);
        assertEq(sale.maxPrices(alice), 10e6);

        // Should fail after sale ends
        vm.prank(admin);
        sale.endSale();

        vm.expectRevert(abi.encodeWithSelector(SealedBidTokenSale.SaleAlreadyEnded.selector, block.timestamp));
        vm.prank(alice);
        sale.updateMaxPrice(2e6);
    }

    function testUpdateMaxPrice_StateChanges() public {
        vm.warp(startTime + 1);

        // Initial state
        assertEq(sale.maxPrices(alice), 0);

        // First update
        uint256 firstPrice = 10e6;
        vm.prank(alice);
        sale.updateMaxPrice(firstPrice);
        assertEq(sale.maxPrices(alice), firstPrice);

        // Update to higher price
        uint256 higherPrice = 20e6;
        vm.prank(alice);
        sale.updateMaxPrice(higherPrice);
        assertEq(sale.maxPrices(alice), higherPrice);

        // Update to lower price
        uint256 lowerPrice = 15e6;
        vm.prank(alice);
        sale.updateMaxPrice(lowerPrice);
        assertEq(sale.maxPrices(alice), lowerPrice);

        // Update to same price
        vm.prank(alice);
        sale.updateMaxPrice(lowerPrice);
        assertEq(sale.maxPrices(alice), lowerPrice);
    }

    function testUpdateMaxPrice_MultipleUsersIndependently() public {
        vm.warp(startTime + 1);

        // Update prices for different users
        vm.prank(alice);
        sale.updateMaxPrice(10e6);
        assertEq(sale.maxPrices(alice), 10e6);

        vm.prank(bob);
        sale.updateMaxPrice(20e6);
        assertEq(sale.maxPrices(bob), 20e6);

        // Verify changes don't affect other users
        assertEq(sale.maxPrices(alice), 10e6);
        assertEq(sale.maxPrices(bob), 20e6);

        // Update alice's price again
        vm.prank(alice);
        sale.updateMaxPrice(30e6);
        assertEq(sale.maxPrices(alice), 30e6);
        assertEq(sale.maxPrices(bob), 20e6);
    }

    function testUpdateMaxPrice_WithDeposit() public {
        vm.warp(startTime + 1);

        // Setup initial deposit with maxPrice
        uint256 depositAmount = 1000 * 1e6;
        uint256 initialMaxPrice = 10 * 1e6;

        usdc.mint(alice, depositAmount);
        vm.prank(alice);
        usdc.approve(address(sale), depositAmount);

        vm.prank(alice);
        sale.deposit(depositAmount, initialMaxPrice);
        assertEq(sale.maxPrices(alice), initialMaxPrice);

        // Update maxPrice after deposit
        uint256 newMaxPrice = 30 * 1e6;
        vm.prank(alice);
        sale.updateMaxPrice(newMaxPrice);
        assertEq(sale.maxPrices(alice), newMaxPrice);

        // Verify deposit amount remains unchanged
        assertEq(sale.deposits(alice), depositAmount);
    }

    function testUpdateMaxPrice_EventEmission() public {
        vm.warp(startTime + 1);

        uint256 oldPrice = 0; // Initial price
        uint256 newPrice = 10e6;

        vm.expectEmit(true, false, false, true);
        emit SealedBidTokenSale.MaxPriceUpdated(alice, oldPrice, newPrice);

        vm.prank(alice);
        sale.updateMaxPrice(newPrice);
    }

    /* ============ saleStatus ============ */

    function testSaleStatus_InitialState() public view {
        // Check initial state
        SealedBidTokenSale.SaleInfo memory info = sale.saleStatus(alice);

        assertEq(info.startTime, startTime, "Start time should match constructor");
        assertEq(info.minimumCap, MIN_CAP, "Minimum cap should match constructor");
        assertEq(info.totalDeposited, 0, "Total deposited should be 0");
        assertEq(info.totalWithdrawn, 0, "Total withdrawn should be 0");
        assertEq(info.totalUsdcClaimed, 0, "Total USDC claimed should be 0");
        assertEq(info.totalSaleTokenClaimed, 0, "Total sale token claimed should be 0");
        assertEq(info.saleEnded, false, "Sale should not be ended");
        assertEq(info.capReached, false, "Cap should not be reached");
        assertEq(info.hasClaimed, false, "User should not have claimed");
        assertEq(info.depositAmount, 0, "User deposit amount should be 0");
        assertEq(info.contributorCount, 0, "Contributor count should be 0");
        assertEq(info.maxPrice, 0, "maxPrice should be 0");
    }

    function testSaleStatus_AfterDeposit() public {
        // Setup deposit
        vm.warp(startTime + 1);
        uint256 amount = 1000 * 1e6;

        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        // Make deposit
        vm.prank(alice);
        sale.deposit(amount, maxPrice);

        // Check state after deposit
        SealedBidTokenSale.SaleInfo memory info = sale.saleStatus(alice);

        assertEq(info.totalDeposited, amount, "Total deposited should match deposit");
        assertEq(info.depositAmount, amount, "User deposit should match deposit");
        assertEq(info.contributorCount, 1, "Contributor count should be 1");
    }

    function testSaleStatus_AfterWithdraw() public {
        // Setup deposit
        vm.warp(startTime + 1);
        uint256 amount = 1000 * 1e6;

        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        vm.prank(alice);
        sale.deposit(amount, maxPrice);

        // End sale without reaching cap
        vm.warp(endTime);
        vm.prank(admin);
        sale.endSale();

        // Withdraw
        vm.prank(alice);
        sale.withdraw();

        // Check state after withdrawal
        SealedBidTokenSale.SaleInfo memory info = sale.saleStatus(alice);

        assertEq(info.totalWithdrawn, amount, "Total withdrawn should match deposit");
        assertEq(info.depositAmount, 0, "User deposit should be 0 after withdrawal");
        assertEq(info.saleEnded, true, "Sale should be ended");
        assertEq(info.maxPrice, maxPrice, "maxPrice should be maxPrice");
    }

    function testSaleStatus_AfterSuccessfulSaleAndClaim() public {
        // Setup successful sale
        vm.warp(startTime + 1);

        usdc.mint(alice, MAX_CAP);
        saleToken.mint(address(sale), saleTokenAllocation);

        vm.prank(alice);
        usdc.approve(address(sale), MAX_CAP);

        vm.prank(alice);
        sale.deposit(MAX_CAP, maxPrice);

        // End sale
        vm.warp(endTime);
        vm.prank(admin);
        sale.endSale();

        // Set merkle root and claim
        vm.prank(admin);
        sale.setMerkleRoot(merkleRoot);

        sale.claimTokens(saleTokenAllocation, usdcAllocation, proof, alice);

        // Check state after claim
        SealedBidTokenSale.SaleInfo memory info = sale.saleStatus(alice);

        assertEq(info.totalUsdcClaimed, usdcAllocation, "Total USDC claimed should match allocation");
        assertEq(info.totalSaleTokenClaimed, saleTokenAllocation, "Total sale token claimed should match allocation");
        assertEq(info.saleEnded, true, "Sale should be ended");
        assertEq(info.capReached, true, "Cap should be reached");
        assertEq(info.hasClaimed, true, "User should have claimed");
        assertEq(info.maxPrice, maxPrice, "maxPrice should be maxPrice");
    }

    function testSaleStatus_MultipleUsers() public {
        // Setup deposits for multiple users
        vm.warp(startTime + 1);
        uint256 amount = 1000 * 1e6;

        // Setup Alice
        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);
        vm.prank(alice);
        sale.deposit(amount, maxPrice);

        // Setup Bob
        usdc.mint(bob, amount);
        vm.prank(bob);
        usdc.approve(address(sale), amount);
        vm.prank(bob);
        sale.deposit(amount, maxPrice);

        // Check states for both users
        SealedBidTokenSale.SaleInfo memory aliceInfo = sale.saleStatus(alice);
        SealedBidTokenSale.SaleInfo memory bobInfo = sale.saleStatus(bob);

        assertEq(aliceInfo.totalDeposited, amount * 2, "Total deposited should include both deposits");
        assertEq(bobInfo.totalDeposited, amount * 2, "Total deposited should be same for all users");
        assertEq(aliceInfo.depositAmount, amount, "Alice deposit should match her deposit");
        assertEq(bobInfo.depositAmount, amount, "Bob deposit should match his deposit");
        assertEq(aliceInfo.contributorCount, 2, "Contributor count should be 2");
        assertEq(bobInfo.contributorCount, 2, "Contributor count should be same for all users");
    }

    /* ============ saleStatus ============ */

    function testEmissaryDeposit_During_EarlyAccess() public {
        // Set time to early access period
        vm.warp(preStartTime + 1);

        uint256 amount = 1000 * 1e6;
        uint256 initialEmissaryCount = sale.currentEmissaryCount();

        // Setup deposit
        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        // Make deposit during early access
        vm.prank(alice);
        sale.deposit(amount, maxPrice);

        // Verify emissary status
        assertTrue(sale.isEmissary(alice));
        assertEq(sale.currentEmissaryCount(), initialEmissaryCount + 1);
        assertEq(sale.deposits(alice), amount);
    }

    function testEmissaryDeposit_RevertWhen_MaxEmissariesReached() public {
        // Set time to early access period
        vm.warp(preStartTime + 1);

        uint256 amount = 1000 * 1e6;

        // Fill up emissary slots
        for (uint256 i = 0; i < sale.MAX_EMISSARIES(); i++) {
            address emissary = address(uint160(i + 1000)); // Generate unique addresses

            usdc.mint(emissary, amount);
            vm.prank(emissary);
            usdc.approve(address(sale), amount);

            vm.prank(emissary);
            sale.deposit(amount, maxPrice);
        }

        // Try to add one more emissary
        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        vm.expectRevert(SealedBidTokenSale.EmissaryFull.selector);
        vm.prank(alice);
        sale.deposit(amount, maxPrice);
    }

    function testEmissaryDeposit_MultipleDeposits_SameEmissary() public {
        // Set time to early access period
        vm.warp(preStartTime + 1);

        uint256 amount = 1000 * 1e6;
        uint256 initialEmissaryCount = sale.currentEmissaryCount();

        // First deposit
        usdc.mint(alice, amount * 2);
        vm.prank(alice);
        usdc.approve(address(sale), amount * 2);

        vm.prank(alice);
        sale.deposit(amount, maxPrice);

        // Second deposit from same emissary
        vm.prank(alice);
        sale.deposit(amount, maxPrice);

        // Verify emissary count only increased once
        assertTrue(sale.isEmissary(alice));
        assertEq(sale.currentEmissaryCount(), initialEmissaryCount + 1);
        assertEq(sale.deposits(alice), amount * 2);
    }

    function testDeposit_After_EmissaryPeriod() public {
        // Set time after early access period
        vm.warp(startTime + 1);

        uint256 amount = 1000 * 1e6;

        // Setup deposit
        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        // Make regular deposit after early access
        vm.prank(alice);
        sale.deposit(amount, maxPrice);

        // Verify not counted as emissary
        assertFalse(sale.isEmissary(alice));
        assertEq(sale.currentEmissaryCount(), 0);
        assertEq(sale.deposits(alice), amount);
    }

    function testSaleStatus_EmissaryCount() public {
        // Set time to early access period
        vm.warp(preStartTime + 1);

        uint256 amount = 1000 * 1e6;

        // Add a few emissaries
        for (uint256 i = 0; i < 3; i++) {
            address emissary = address(uint160(i + 1000));

            usdc.mint(emissary, amount);
            vm.prank(emissary);
            usdc.approve(address(sale), amount);

            vm.prank(emissary);
            sale.deposit(amount, maxPrice);
        }

        // Check emissary count in status
        SealedBidTokenSale.SaleInfo memory info = sale.saleStatus(alice);
        assertEq(info.currentEmissaryCount, 3);
    }

    function testEmissaryDeposit_Boundaries() public {
        uint256 amount = 1000 * 1e6;

        // Try just before preStartTime
        vm.warp(preStartTime - 1);
        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(sale), amount);

        vm.expectRevert(
            abi.encodeWithSelector(SealedBidTokenSale.SaleNotStarted.selector, preStartTime - 1, preStartTime)
        );
        vm.prank(alice);
        sale.deposit(amount, maxPrice);

        // Try at exactly preStartTime
        vm.warp(preStartTime);
        vm.prank(alice);
        sale.deposit(amount, maxPrice);
        assertTrue(sale.isEmissary(alice));

        // Try just before startTime
        vm.warp(startTime - 1);
        usdc.mint(bob, amount);
        vm.prank(bob);
        usdc.approve(address(sale), amount);

        vm.prank(bob);
        sale.deposit(amount, maxPrice);
        assertTrue(sale.isEmissary(bob));

        // Try at exactly startTime
        vm.warp(startTime);
        usdc.mint(address(0x123), amount);
        vm.prank(address(0x123));
        usdc.approve(address(sale), amount);

        vm.prank(address(0x123));
        sale.deposit(amount, maxPrice);
        assertFalse(sale.isEmissary(address(0x123)));
    }
}

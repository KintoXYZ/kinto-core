// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";
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
        sale.deposit(amount);
    }

    function testDeposit_RevertWhen_ZeroAmount() public {
        // Advance time to start of sale
        vm.warp(startTime + 1);

        // Try to deposit zero amount
        vm.prank(alice);
        vm.expectRevert(SealedBidTokenSale.ZeroDeposit.selector);
        sale.deposit(0);
    }

    function testDeposit_MultipleDeposits() public {
        // Advance time to start of sale
        vm.warp(startTime + 1);

        uint256 firstAmount = 1000 * 1e6;
        uint256 secondAmount = 2000 * 1e6;
        uint256 totalAmount = firstAmount + secondAmount;

        // Mint and approve USDC for both deposits
        usdc.mint(alice, totalAmount);
        vm.prank(alice);
        usdc.approve(address(sale), totalAmount);

        // Make first deposit
        vm.prank(alice);
        sale.deposit(firstAmount);

        // Make second deposit
        vm.prank(alice);
        sale.deposit(secondAmount);

        // Verify final state
        assertEq(sale.deposits(alice), totalAmount);
        assertEq(sale.totalDeposited(), totalAmount);
        assertEq(usdc.balanceOf(address(sale)), totalAmount);
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
        sale.deposit(aliceAmount);

        vm.prank(bob);
        sale.deposit(bobAmount);

        // Verify final state
        assertEq(sale.deposits(alice), aliceAmount);
        assertEq(sale.deposits(bob), bobAmount);
        assertEq(sale.totalDeposited(), totalAmount);
        assertEq(usdc.balanceOf(address(sale)), totalAmount);
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
        sale.deposit(amount);

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
        sale.deposit(amount);

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
        sale.deposit(aliceAmount);

        // Bob's deposit
        usdc.mint(bob, bobAmount);
        vm.prank(bob);
        usdc.approve(address(sale), bobAmount);

        vm.prank(bob);
        sale.deposit(bobAmount);

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
        sale.deposit(amount);

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
        sale.deposit(amount);

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
        sale.deposit(amount);

        // End sale successfully
        vm.prank(admin);
        sale.endSale();

        // Attempt withdrawal on successful sale
        vm.prank(alice);
        vm.expectRevert(SealedBidTokenSale.SaleWasSuccessful.selector);
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
        sale.deposit(aliceAmount);

        // Setup and execute Bob's deposit
        usdc.mint(bob, bobAmount);
        vm.prank(bob);
        usdc.approve(address(sale), bobAmount);

        vm.prank(bob);
        sale.deposit(bobAmount);

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
        sale.deposit(amount);

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
        sale.deposit(MAX_CAP);

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
        sale.deposit(amount);

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
        sale.deposit(MAX_CAP);

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
        sale.deposit(MAX_CAP);

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
        sale.deposit(MAX_CAP);

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
        sale.deposit(MAX_CAP);

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
        sale.deposit(MAX_CAP);

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
        sale.deposit(MIN_CAP);

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
        sale.deposit(amount);

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
        sale.deposit(MIN_CAP);

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
        sale.deposit(MIN_CAP);

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
        sale.deposit(MIN_CAP);

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
        sale.deposit(depositAmount);

        vm.prank(admin);
        sale.endSale();

        // Check initial balances
        uint256 initialTreasuryBalance = usdc.balanceOf(TREASURY);
        uint256 initialSaleBalance = usdc.balanceOf(address(sale));

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
        sale.deposit(depositAmount);

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
        sale.deposit(depositAmount);

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
        sale.deposit(depositAmount);

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
        sale.deposit(aliceAmount);

        // Bob's deposit
        usdc.mint(bob, bobAmount);
        vm.prank(bob);
        usdc.approve(address(sale), bobAmount);
        vm.prank(bob);
        sale.deposit(bobAmount);

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
        sale.deposit(depositAmount);

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
        sale.deposit(depositAmount);

        vm.prank(admin);
        sale.endSale();

        uint256 initialTreasuryBalance = usdc.balanceOf(TREASURY);

        // Withdraw proceeds
        vm.prank(admin);
        sale.withdrawProceeds();

        assertEq(usdc.balanceOf(TREASURY), initialTreasuryBalance + depositAmount);
        assertEq(usdc.balanceOf(address(sale)), 0);
    }
}

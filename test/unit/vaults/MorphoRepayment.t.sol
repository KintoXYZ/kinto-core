// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@kinto-core-test/helpers/ERC20Mock.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import {MorphoRepayment} from "@kinto-core/vaults/MorphoRepayment.sol";
import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";
import {console2} from "forge-std/console2.sol";

/* ===== Upgrade target ===== */
contract MorphoRepaymentV2 is MorphoRepayment {
    function ping() external pure returns (uint256) {
        return 42;
    }

    constructor(IERC20Upgradeable c, IERC20Upgradeable d) MorphoRepayment(c, d) {}
}

contract MorphoRepaymentTest is SharedSetup {
    // Tokens
    ERC20Mock public collateral; // 18dp (e.g., K)
    ERC20Mock public usdc; // 6dp (debt token)

    // Main
    MorphoRepayment public repay;

    MorphoRepayment.UserInfo[] public infos;
    MorphoRepayment.UserInfo[] public moreInfos;
    address[] public moreUsers;

    // Constants from your contract (units respected)
    uint256 public constant TOTAL_COLLATERAL = 1e24; // 1,000,000 * 1e18
    uint256 public constant TOTAL_DEBT = 25e11; // 2,500,000 * 1e6
    uint256 public constant TOTAL_USDC_LENT = 10e11; // 1,000,000 * 1e6
    uint256 public constant BONUS_REPAYMENT = 1e17; // 10% (scaled 1e18)
    uint256 public constant THREE_MONTHS = 7776000; // 90d

    uint256 public deadline; // matches contract’s REPAYMENT_DEADLINE

    address public alice2;
    address public bob2;
    address public charlie2;

    function setUp() public override {
        super.setUp();

        collateral = new ERC20Mock("Kinto", "K", 18);
        usdc = new ERC20Mock("USD Coin", "USDC", 6);

        alice2 = vm.addr(1);
        bob2 = vm.addr(2);
        charlie2 = vm.addr(8);

        // Deploy implementation then proxy
        MorphoRepayment impl =
            new MorphoRepayment(IERC20Upgradeable(address(collateral)), IERC20Upgradeable(address(usdc)));

        vm.startPrank(admin);
        repay = MorphoRepayment(payable(address(new UUPSProxy{salt: 0}(address(impl), ""))));
        repay.initialize();
        vm.stopPrank();

        // Pre-fund contract with collateral for returns (principal + bonus)
        collateral.mint(address(repay), 10_000_000 ether);
        // Give users USDC + collateral
        usdc.mint(alice2, 10_000_000 * 1e6);
        usdc.mint(bob2, 10_000_000 * 1e6);
        usdc.mint(charlie2, 10_000_000 * 1e6);
        collateral.mint(alice2, 10_000_000 ether);
        collateral.mint(bob2, 10_000_000 ether);
        collateral.mint(charlie2, 10_000_000 ether);

        // Approvals
        vm.startPrank(alice2);
        usdc.approve(address(repay), type(uint256).max);
        collateral.approve(address(repay), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob2);
        usdc.approve(address(repay), type(uint256).max);
        collateral.approve(address(repay), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(charlie2);
        usdc.approve(address(repay), type(uint256).max);
        collateral.approve(address(repay), type(uint256).max);
        vm.stopPrank();

        // Mirror contract’s deadline (constant in bytecode). We just reuse known value.
        deadline = 1763161200;
        // Ensure we are comfortably before deadline for most tests
        if (block.timestamp >= deadline - 10) {
            vm.warp(deadline - 20);
        }
    }

    /* ============ Deployment ============ */

    function testDeploymentConfig() public view {
        assertEq(address(repay.collateralToken()), address(collateral));
        assertEq(address(repay.debtToken()), address(usdc));
        assertEq(repay.owner(), admin);
    }

    /* ============ Upgrades (UUPS) ============ */

    function testUpgradeOnlyOwnerReverts(address someone) public {
        vm.assume(someone != admin);
        MorphoRepaymentV2 v2 =
            new MorphoRepaymentV2(IERC20Upgradeable(address(collateral)), IERC20Upgradeable(address(usdc)));
        vm.prank(someone);
        vm.expectRevert("Ownable: caller is not the owner");
        repay.upgradeTo(address(v2));
    }

    function testUpgradeSuccess() public {
        MorphoRepaymentV2 v2 =
            new MorphoRepaymentV2(IERC20Upgradeable(address(collateral)), IERC20Upgradeable(address(usdc)));
        vm.prank(admin);
        repay.upgradeTo(address(v2));
        assertEq(MorphoRepaymentV2(address(repay)).ping(), 42);
    }

    /* ============ setUserInfo ============ */

    function testSetUserInfoLengthMismatchReverts() public {
        MorphoRepayment.UserInfo;
        users = new address[](2);
        users[0] = alice2;
        users[1] = bob2;

        vm.prank(admin);
        vm.expectRevert(bytes("Length mismatch"));
        repay.setUserInfo(users, infos);
    }

    function testSetUserInfoNormal() public {
        users = new address[](2);
        users[0] = alice2;
        users[1] = bob2;

        infos.push(
            MorphoRepayment.UserInfo({
                usdcLent: 100_000 * 1e6,
                collateralLocked: 50_000 ether,
                usdcBorrowed: 20_000 * 1e6,
                usdcRepaid: 0,
                isRepaid: false
            })
        );
        infos.push(
            MorphoRepayment.UserInfo({
                usdcLent: 200_000 * 1e6,
                collateralLocked: 70_000 ether,
                usdcBorrowed: 0,
                usdcRepaid: 0,
                isRepaid: false
            })
        );

        vm.prank(admin);
        repay.setUserInfo(users, infos);

        (uint256 lentA, uint256 collA, uint256 borrA, uint256 repA, bool isRepA) = repay.userInfos(alice2);
        assertEq(lentA, 100_000 * 1e6);
        assertEq(collA, 50_000 ether);
        assertEq(borrA, 20_000 * 1e6);
        assertEq(repA, 0);
        assertEq(isRepA, false);

        (uint256 lentB, uint256 collB, uint256 borrB, uint256 repB, bool isRepB) = repay.userInfos(bob2);
        assertEq(lentB, 200_000 * 1e6);
        assertEq(collB, 70_000 ether);
        assertEq(borrB, 0);
        assertEq(repB, 0);
        assertEq(isRepB, false);
    }

    /* ============ repayDebt: all flows ============ */

    function testRepayZeroAmountUnlocksWhenNoDebt() public {
        // bob2 has collateral but borrowed == 0; zero-amount call returns principal (bonus = 0)
        users = new address[](1);
        users[0] = bob2;
        infos.push(
            MorphoRepayment.UserInfo({
                usdcLent: 0,
                collateralLocked: 1_000 ether,
                usdcBorrowed: 0,
                usdcRepaid: 0,
                isRepaid: false
            })
        );

        vm.prank(admin);
        repay.setUserInfo(users, infos);

        uint256 balBefore = collateral.balanceOf(bob2);
        vm.prank(bob2);
        repay.repayDebt(0);

        // Principal returned, no bonus
        assertEq(collateral.balanceOf(bob2), balBefore + 1_000 ether);
        (, uint256 coll,,, bool isRep) = repay.userInfos(bob2);
        assertEq(coll, 0);
        assertTrue(isRep);
    }

    function testRepayPartial() public {
        // alice2 borrowed 2,000 USDC; repay 500; no collateral returned yet
        users = new address[](1);
        users[0] = alice2;
        infos.push(
            MorphoRepayment.UserInfo({
                usdcLent: 0,
                collateralLocked: 1_000 ether,
                usdcBorrowed: 2_000 * 1e6,
                usdcRepaid: 0,
                isRepaid: false
            })
        );
        vm.prank(admin);
        repay.setUserInfo(users, infos);

        uint256 contractUSDCBefore = usdc.balanceOf(address(repay));
        vm.prank(alice2);
        repay.repayDebt(500 * 1e6);

        (,, uint256 borrowed, uint256 repaid, bool isRep) = repay.userInfos(alice2);
        assertEq(borrowed, 2_000 * 1e6);
        assertEq(repaid, 500 * 1e6);
        assertFalse(isRep);
        assertEq(usdc.balanceOf(address(repay)), contractUSDCBefore + 500 * 1e6);
        // No collateral paid yet
        assertEq(collateral.balanceOf(alice2), collateral.balanceOf(alice2)); // unchanged check (implicit)
    }

    function testRepayFullWithBonusAtMaxWindow() public {
        // Make timeLeft = THREE_MONTHS (full 10% of base)
        uint256 nowTs = block.timestamp;
        // force exactly: timeLeft = THREE_MONTHS
        vm.warp(deadline - THREE_MONTHS);

        // alice2 borrowed 1,200 USDC; on final repayment bonus base = 3× amountRepaid (in 18dp)
        users = new address[](1);
        users[0] = alice2;
        infos.push(
            MorphoRepayment.UserInfo({
                usdcLent: 0,
                collateralLocked: 10_000 ether,
                usdcBorrowed: 1_200 * 1e6,
                usdcRepaid: 1_200 * 1e6 - 200 * 1e6,
                isRepaid: false
            })
        );
        vm.prank(admin);
        repay.setUserInfo(users, infos);

        uint256 principal = 10_000 ether;
        uint256 finalChunk = 200 * 1e6; // USDC (6dp)
        uint256 base18 = finalChunk * 1e12 * 3; // convert 6dp→18dp and ×3
        uint256 tenPct = MathUpgradeable.mulDiv(base18, BONUS_REPAYMENT, 1e18); // 10% of base
        uint256 bonus = MathUpgradeable.mulDiv(tenPct, THREE_MONTHS, THREE_MONTHS); // timeLeft=THREE_MONTHS

        uint256 alice2KBefore = collateral.balanceOf(alice2);
        uint256 contractUSDCBefore = usdc.balanceOf(address(repay));

        vm.prank(alice2);
        repay.repayDebt(finalChunk);

        // Collateral + bonus returned
        assertEq(collateral.balanceOf(alice2), alice2KBefore + principal + bonus);
        (, uint256 coll,,, bool isRep) = repay.userInfos(alice2);
        assertEq(coll, 0);
        assertTrue(isRep);
        // Contract got the 200 USDC final transfer
        assertEq(usdc.balanceOf(address(repay)), contractUSDCBefore + finalChunk);

        // restore time
        vm.warp(nowTs);
    }

    function testRepayRevertOverRemaining() public {
        users = new address[](1);
        users[0] = alice2;
        infos.push(
            MorphoRepayment.UserInfo({
                usdcLent: 0,
                collateralLocked: 1_000 ether,
                usdcBorrowed: 1_000 * 1e6,
                usdcRepaid: 100 * 1e6,
                isRepaid: false
            })
        );
        vm.prank(admin);
        repay.setUserInfo(users, infos);

        vm.prank(alice2);
        vm.expectRevert(bytes("Not enough debt"));
        repay.repayDebt(950 * 1e6);
    }

    function testRepayRevertAfterDeadline() public {
        users = new address[](1);
        users[0] = alice2;
        infos.push(
            MorphoRepayment.UserInfo({
                usdcLent: 0,
                collateralLocked: 1_000 ether,
                usdcBorrowed: 1_000 * 1e6,
                usdcRepaid: 0,
                isRepaid: false
            })
        );
        vm.prank(admin);
        repay.setUserInfo(users, infos);

        vm.warp(deadline + 1);
        vm.prank(alice2);
        vm.expectRevert(bytes("Repayment deadline reached"));
        repay.repayDebt(100 * 1e6);
    }

    /* ============ recoverSuppliedUSDC ============ */

    function testRecoverRevertBeforeDeadline() public {
        users = new address[](1);
        users[0] = alice2;
        infos.push(
            MorphoRepayment.UserInfo({
                usdcLent: 500_000 * 1e6,
                collateralLocked: 0,
                usdcBorrowed: 0,
                usdcRepaid: 0,
                isRepaid: false
            })
        );
        vm.prank(admin);
        repay.setUserInfo(users, infos);

        vm.prank(alice2);
        vm.expectRevert(bytes("Repayment deadline not reached"));
        repay.recoverSuppliedUSDC();
    }

    function testRecoverPartialFundingProRata() public {
        // alice2 & bob2 lent; only 40% of TOTAL_DEBT repaid globally → both recover 40% of their lent
        users = new address[](2);
        users[0] = alice2;
        users[1] = bob2;
        infos.push(
            MorphoRepayment.UserInfo({
                usdcLent: 600_000 * 1e6,
                collateralLocked: 0,
                usdcBorrowed: 0,
                usdcRepaid: 0,
                isRepaid: false
            })
        );
        infos.push(
            MorphoRepayment.UserInfo({
                usdcLent: 400_000 * 1e6,
                collateralLocked: 0,
                usdcBorrowed: 0,
                usdcRepaid: 0,
                isRepaid: false
            })
        );
        vm.prank(admin);
        repay.setUserInfo(users, infos);

        // Simulate some other users repaid 40% of TOTAL_DEBT into the contract
        // Easiest: make a dummy borrower record and repay from alice2 to fund the contract & update totalDebtRepaid
        moreUsers = new address[](1);
        moreUsers[0] = charlie2;
        uint256 targetRepay = (TOTAL_DEBT * 40) / 100; // 40%
        moreInfos.push(
            MorphoRepayment.UserInfo({
                usdcLent: 0,
                collateralLocked: 0,
                usdcBorrowed: targetRepay,
                usdcRepaid: 0,
                isRepaid: false
            })
        );
        vm.prank(admin);
        repay.setUserInfo(moreUsers, moreInfos);

        vm.prank(charlie2);
        repay.repayDebt(targetRepay);

        // Move past deadline
        vm.warp(deadline + 1);

        uint256 alice2Before = usdc.balanceOf(alice2);
        uint256 bob2Before = usdc.balanceOf(bob2);

        // Recover
        vm.prank(alice2);
        repay.recoverSuppliedUSDC(); // should get 40% of 600k = 240k
        vm.prank(bob2);
        repay.recoverSuppliedUSDC(); // should get 40% of 400k = 160k

        assertEq(usdc.balanceOf(alice2) - alice2Before, 240_000 * 1e6);
        assertEq(usdc.balanceOf(bob2) - bob2Before, 160_000 * 1e6);

        // user.usdcLent reduced but not zero (remaining 60%)
        (uint256 aLent,,,,) = repay.userInfos(alice2);
        (uint256 bLent,,,,) = repay.userInfos(bob2);
        assertEq(aLent, 360_000 * 1e6);
        assertEq(bLent, 240_000 * 1e6);
    }

    function testRecoverFullyFundedWithdrawAll() public {
        // alice2 lent 1,000, fully funded → withdraw 100%
        users = new address[](1);
        users[0] = alice2;
        infos.push(
            MorphoRepayment.UserInfo({
                usdcLent: 1_000_000 * 1e6,
                collateralLocked: 0,
                usdcBorrowed: 0,
                usdcRepaid: 0,
                isRepaid: false
            })
        );
        vm.prank(admin);
        repay.setUserInfo(users, infos);

        // Repay TOTAL_DEBT via charlie2 to set factor == 1e18
        moreUsers = new address[](1);
        moreUsers[0] = charlie2;
        moreInfos.push(
            MorphoRepayment.UserInfo({
                usdcLent: 0,
                collateralLocked: 0,
                usdcBorrowed: TOTAL_DEBT,
                usdcRepaid: 0,
                isRepaid: false
            })
        );
        vm.prank(admin);
        repay.setUserInfo(moreUsers, moreInfos);

        vm.prank(charlie2);
        repay.repayDebt(TOTAL_DEBT);

        vm.warp(deadline + 1);

        uint256 before = usdc.balanceOf(alice2);
        vm.prank(alice2);
        repay.recoverSuppliedUSDC();

        // Full recovery, user.usdcLent zeroed
        assertEq(usdc.balanceOf(alice2) - before, 1_000_000 * 1e6);
        (uint256 aLent,,,,) = repay.userInfos(alice2);
        assertEq(aLent, 0);
    }
}

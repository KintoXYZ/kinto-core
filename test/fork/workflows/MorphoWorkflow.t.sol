// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";
import {Bridger} from "@kinto-core/bridger/Bridger.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";

import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {MorphoWorkflow} from "@kinto-core/access/workflows/MorphoWorkflow.sol";
import {BridgeDataHelper} from "@kinto-core-test/helpers/BridgeDataHelper.sol";
import {Id, IMorpho, MarketParams, Position, Market} from "@kinto-core/interfaces/external/IMorpho.sol";
import {IPreLiquidationFactory} from "@kinto-core/interfaces/external/IMorphoPreLiquidationFactory.sol";
import {IPreLiquidation, PreLiquidationParams} from "@kinto-core/interfaces/external/IMorphoPreLiquidation.sol";

interface IOracle {
    function price() external view returns (uint256);
}

import "@kinto-core-test/fork/const.sol";
import "@kinto-core-test/helpers/UUPSProxy.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/helpers/ArtifactsReader.sol";
import {ForkTest} from "@kinto-core-test/helpers/ForkTest.sol";
import {AccessRegistryHarness} from "@kinto-core-test/harness/AccessRegistryHarness.sol";
import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";
import {SuperToken} from "@kinto-core/tokens/bridged/SuperToken.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MorphoWorkflowTest is SignatureHelper, ForkTest, ArtifactsReader, Constants, BridgeDataHelper {
    using stdJson for string;

    Bridger internal bridger;
    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    MorphoWorkflow internal morphoWorkflow;
    MarketParams internal marketParams;
    Id internal marketId;
    address internal kintoWallet = address(0x1234); // Non-zero Kinto wallet address

    // Morpho protocol constants
    address constant MORPHO = 0x6c247b1F6182318877311737BaC0844bAa518F5e;
    address constant LOAN_TOKEN = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC.e on Arbitrum
    address constant COLLATERAL_TOKEN = 0x010700AB046Dd8e92b0e3587842080Df36364ed3; // $K on Arbitrum
    address constant COLLATERAL_MINTER = 0x702BD1AC995Bf22B8B711A1Ce9796bAc9bdd1f1f;
    address constant ORACLE = 0x2964aB84637d4c3CAF0Fd968be1c97D9990de925;
    address constant IRM = 0x66F30587FB8D4206918deb78ecA7d5eBbafD06DA;
    uint256 constant LLTV = 625000000000000000; // 62.5%
    address constant PRE_LIQUIDATION_FACTORY = 0x635c31B5DF1F7EFbCbC07E302335Ef4230758e3d;

    function setUp() public override {
        super.setUp();

        bridger = Bridger(payable(_getChainDeployment("Bridger")));
        accessRegistry = AccessRegistry(_getChainDeployment("AccessRegistry"));

        deploy();
    }

    function deploy() internal {
        accessPoint = accessRegistry.deployFor(address(alice0));
        vm.label(address(accessPoint), "accessPoint");

        morphoWorkflow = new MorphoWorkflow();
        vm.label(address(morphoWorkflow), "morphoWorkflow");

        vm.prank(accessRegistry.owner());
        accessRegistry.allowWorkflow(address(morphoWorkflow));
    }

    function setUpChain() public virtual override {
        setUpArbitrumFork();
        // Use a recent block
        vm.rollFork(334386318);
    }

    function _getMarketParams() internal pure returns (MarketParams memory) {
        return MarketParams({
            loanToken: LOAN_TOKEN,
            collateralToken: COLLATERAL_TOKEN,
            oracle: ORACLE,
            irm: IRM,
            lltv: LLTV
        });
    }

    function testLendAndBorrow() public {
        collateralAmount = 10 ether; // 10 $K
        uint256 borrowAmount = 5e6; // 5 USDC.e

        // Use a valid BridgeData from BridgeDataHelper for USDC on Arbitrum
        IBridger.BridgeData memory data = bridgeData[ARBITRUM_CHAINID][USDC_ARBITRUM];

        // Deal collateral to the access point
        vm.prank(COLLATERAL_MINTER);
        SuperToken(COLLATERAL_TOKEN).mint(address(accessPoint), collateralAmount);

        // Get initial balances
        uint256 initialCollateralBalance = IERC20(COLLATERAL_TOKEN).balanceOf(address(accessPoint));
        uint256 initialLoanBalance = IERC20(LOAN_TOKEN).balanceOf(address(accessPoint));

        // Prepare workflow data with valid BridgeData
        bytes memory workflowData = abi.encodeWithSelector(
            MorphoWorkflow.lendAndBorrow.selector, collateralAmount, borrowAmount, kintoWallet, data
        );

        uint256 vaultBalanceBefore = ERC20(LOAN_TOKEN).balanceOf(address(data.vault));

        // Execute the workflow
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), workflowData);

        // Check that collateral was supplied
        assertEq(
            IERC20(COLLATERAL_TOKEN).balanceOf(address(accessPoint)),
            initialCollateralBalance - collateralAmount,
            "Collateral balance should have decreased"
        );

        // Check that loan was received
        assertEq(ERC20(LOAN_TOKEN).balanceOf(address(data.vault)), vaultBalanceBefore + borrowAmount);
        assertEq(
            IERC20(LOAN_TOKEN).balanceOf(address(accessPoint)), initialLoanBalance, "Loan balance should have increased"
        );
    }

    function testRepayAndWithdraw() public {
        // First, lend and borrow
        collateralAmount = 10 ether; // 10 $K
        uint256 borrowAmount = 5e6; // 5 USDC.e

        // Mint collateral to the access point
        vm.prank(COLLATERAL_MINTER);
        SuperToken(COLLATERAL_TOKEN).mint(address(accessPoint), collateralAmount);

        // Deal some loan tokens for repayment (use a different approach for USDC.e)
        deal(LOAN_TOKEN, address(accessPoint), borrowAmount);

        // Execute lend and borrow first
        IBridger.BridgeData memory data = bridgeData[ARBITRUM_CHAINID][USDC_ARBITRUM];

        bytes memory lendWorkflowData = abi.encodeWithSelector(
            MorphoWorkflow.lendAndBorrow.selector, collateralAmount, borrowAmount, kintoWallet, data
        );
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), lendWorkflowData);

        // Get balances after lend/borrow
        uint256 loanBalance = IERC20(LOAN_TOKEN).balanceOf(address(accessPoint));
        data = bridgeData[ARBITRUM_CHAINID][K_ARBITRUM];

        // Prepare repay and withdraw workflow data
        bytes memory repayWorkflowData = abi.encodeWithSelector(
            MorphoWorkflow.repayAndWithdraw.selector, borrowAmount, collateralAmount / 2, kintoWallet, data
        );

        // Execute the repay workflow
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), repayWorkflowData);

        // Check that loan was repaid
        assertEq(
            IERC20(LOAN_TOKEN).balanceOf(address(accessPoint)),
            loanBalance - borrowAmount,
            "Loan balance should have decreased"
        );

        // Check that collateral was partially withdrawn
        assertEq(ERC20(COLLATERAL_TOKEN).balanceOf(address(accessPoint)), 0, "AccessPoint balance is wrong");
    }

    function testSupply() public {
        uint256 supplyAmount = 10e6; // 10 USDC

        // Mint tokens to the access point
        deal(LOAN_TOKEN, address(accessPoint), supplyAmount);

        // Get initial balance
        uint256 initialBalance = IERC20(LOAN_TOKEN).balanceOf(address(accessPoint));

        // Prepare workflow data
        bytes memory workflowData = abi.encodeWithSelector(MorphoWorkflow.supply.selector, supplyAmount);

        // Execute the workflow
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), workflowData);

        // Check that tokens were supplied
        assertLt(IERC20(LOAN_TOKEN).balanceOf(address(accessPoint)), initialBalance, "Balance should have decreased");
    }

    function testWithdraw() public {
        // Use a valid BridgeData from BridgeDataHelper for USDC on Arbitrum
        IBridger.BridgeData memory data = bridgeData[ARBITRUM_CHAINID][USDC_ARBITRUM];

        // First, supply some tokens
        uint256 supplyAmount = 10e6; // 10 USDC

        // Mint tokens to the access point
        deal(LOAN_TOKEN, address(accessPoint), supplyAmount);

        // Supply tokens first
        bytes memory supplyWorkflowData = abi.encodeWithSelector(MorphoWorkflow.supply.selector, supplyAmount);
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), supplyWorkflowData);

        // Get balance after supply
        uint256 vaultBalanceBefore = ERC20(LOAN_TOKEN).balanceOf(address(data.vault));

        // Prepare withdraw workflow data (withdraw half)
        bytes memory withdrawWorkflowData =
            abi.encodeWithSelector(MorphoWorkflow.withdraw.selector, supplyAmount / 2, kintoWallet, data);

        // Execute the withdraw workflow
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), withdrawWorkflowData);

        // Check that tokens were withdrawn
        assertEq(
            IERC20(LOAN_TOKEN).balanceOf(address(data.vault)),
            vaultBalanceBefore + supplyAmount / 2,
            "Balance should have increased"
        );
    }

    function testLend() public {
        collateralAmount = 5 ether; // 5 $K

        // Deal collateral to the access point
        vm.prank(COLLATERAL_MINTER);
        SuperToken(COLLATERAL_TOKEN).mint(address(accessPoint), collateralAmount);

        // Get initial balances
        uint256 initialCollateralBalance = IERC20(COLLATERAL_TOKEN).balanceOf(address(accessPoint));

        // Get market parameters and ID
        marketParams = _getMarketParams();
        marketId = morphoWorkflow.id(marketParams);

        // Check initial position (should be zero)
        Position memory positionBefore = IMorpho(MORPHO).position(marketId, address(accessPoint));
        assertEq(positionBefore.collateral, 0, "Initial collateral position should be zero");

        // Prepare workflow data for lend function
        bytes memory workflowData = abi.encodeWithSelector(MorphoWorkflow.lend.selector, collateralAmount);

        // Execute the workflow
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), workflowData);

        // Check that collateral was supplied to Morpho
        assertEq(
            IERC20(COLLATERAL_TOKEN).balanceOf(address(accessPoint)),
            initialCollateralBalance - collateralAmount,
            "Collateral balance should have decreased"
        );

        // Verify position in Morpho
        Position memory positionAfter = IMorpho(MORPHO).position(marketId, address(accessPoint));
        assertEq(positionAfter.collateral, collateralAmount, "Collateral position should match supplied amount");
        assertEq(positionAfter.borrowShares, 0, "No borrow should have occurred");
    }

    function testRepay() public {
        // First, lend and borrow to set up a position
        collateralAmount = 10 ether; // 10 $K
        uint256 borrowAmount = 5e6; // 5 USDC.e

        // Mint collateral to the access point
        vm.prank(COLLATERAL_MINTER);
        SuperToken(COLLATERAL_TOKEN).mint(address(accessPoint), collateralAmount);

        // Get market parameters and ID
        marketParams = _getMarketParams();
        marketId = morphoWorkflow.id(marketParams);

        // Create initial position by lending and borrowing
        IBridger.BridgeData memory data = bridgeData[ARBITRUM_CHAINID][USDC_ARBITRUM];
        bytes memory lendWorkflowData = abi.encodeWithSelector(
            MorphoWorkflow.lendAndBorrow.selector, collateralAmount, borrowAmount, kintoWallet, data
        );
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), lendWorkflowData);

        // Verify the position has been created
        Position memory positionAfterBorrow = IMorpho(MORPHO).position(marketId, address(accessPoint));
        assertTrue(positionAfterBorrow.borrowShares > 0, "Should have borrowed assets");

        // Prepare for repayment - deal tokens to the access point
        uint256 repayAmount = borrowAmount / 2; // Repay half of the loan
        deal(LOAN_TOKEN, address(accessPoint), repayAmount);

        // Snapshot Morpho position before repaying
        Position memory positionBeforeRepay = IMorpho(MORPHO).position(marketId, address(accessPoint));
        uint256 borrowSharesBefore = positionBeforeRepay.borrowShares;

        // Execute repay workflow
        bytes memory repayWorkflowData = abi.encodeWithSelector(MorphoWorkflow.repay.selector, repayAmount);
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), repayWorkflowData);

        // Verify repayment was successful
        Position memory positionAfterRepay = IMorpho(MORPHO).position(marketId, address(accessPoint));

        // Borrow shares should have decreased
        assertLt(
            positionAfterRepay.borrowShares, borrowSharesBefore, "Borrow shares should have decreased after repayment"
        );

        // Collateral should remain unchanged
        assertEq(
            positionAfterRepay.collateral,
            positionBeforeRepay.collateral,
            "Collateral should remain unchanged after repayment"
        );

        // Loan token balance should have decreased in the access point
        assertEq(
            IERC20(LOAN_TOKEN).balanceOf(address(accessPoint)), 0, "All loan tokens should have been used for repayment"
        );
    }

    uint256 internal collateralAmount;
    uint256 internal oraclePrice;
    uint256 internal collateralValueInUSD;
    uint256 internal maxBorrowAmount;

    function testLendAndBorrowTwice() public {
        // First lending and borrowing operation
        uint256 firstCollateralAmount = 10 ether; // 10 $K
        uint256 firstBorrowAmount = 5e6; // 5 USDC.e

        // Use a valid BridgeData from BridgeDataHelper for USDC on Arbitrum
        IBridger.BridgeData memory data = bridgeData[ARBITRUM_CHAINID][USDC_ARBITRUM];

        // Deal collateral to the access point for first operation
        vm.prank(COLLATERAL_MINTER);
        SuperToken(COLLATERAL_TOKEN).mint(address(accessPoint), firstCollateralAmount);

        // Get initial balances
        uint256 initialLoanBalance = IERC20(LOAN_TOKEN).balanceOf(address(accessPoint));

        // Prepare workflow data with valid BridgeData for first operation
        bytes memory firstWorkflowData = abi.encodeWithSelector(
            MorphoWorkflow.lendAndBorrow.selector, firstCollateralAmount, firstBorrowAmount, kintoWallet, data
        );

        uint256 vaultBalanceBefore = ERC20(LOAN_TOKEN).balanceOf(address(data.vault));

        // Execute the first lendAndBorrow operation
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), firstWorkflowData);

        // Get market parameters and ID for verification
        marketParams = _getMarketParams();
        marketId = morphoWorkflow.id(marketParams);

        // Verify the first position
        Position memory positionAfterFirst = IMorpho(MORPHO).position(marketId, address(accessPoint));
        assertEq(positionAfterFirst.collateral, firstCollateralAmount, "First collateral amount doesn't match");
        assertTrue(positionAfterFirst.borrowShares > 0, "First borrow shares should be positive");

        // Verify vault balance increased by first borrow amount
        assertEq(
            ERC20(LOAN_TOKEN).balanceOf(address(data.vault)),
            vaultBalanceBefore + firstBorrowAmount,
            "Vault balance should have increased by first borrow amount"
        );

        // Second lending and borrowing operation
        uint256 secondCollateralAmount = 5 ether; // 5 more $K
        uint256 secondBorrowAmount = 2e6; // 2 more USDC.e

        // Deal more collateral to the access point for second operation
        vm.prank(COLLATERAL_MINTER);
        SuperToken(COLLATERAL_TOKEN).mint(address(accessPoint), secondCollateralAmount);

        // Record vault balance before second operation
        uint256 vaultBalanceAfterFirst = ERC20(LOAN_TOKEN).balanceOf(address(data.vault));

        // Prepare workflow data for second operation
        bytes memory secondWorkflowData = abi.encodeWithSelector(
            MorphoWorkflow.lendAndBorrow.selector, secondCollateralAmount, secondBorrowAmount, kintoWallet, data
        );

        // Execute the second lendAndBorrow operation
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), secondWorkflowData);

        // Verify the updated position after second operation
        Position memory positionAfterSecond = IMorpho(MORPHO).position(marketId, address(accessPoint));

        // Total collateral should be sum of both deposits
        assertEq(
            positionAfterSecond.collateral,
            firstCollateralAmount + secondCollateralAmount,
            "Total collateral should be sum of both deposits"
        );

        // Borrow shares should have increased
        assertGt(
            positionAfterSecond.borrowShares,
            positionAfterFirst.borrowShares,
            "Borrow shares should have increased after second borrow"
        );

        // Verify vault balance increased by second borrow amount
        assertEq(
            ERC20(LOAN_TOKEN).balanceOf(address(data.vault)),
            vaultBalanceAfterFirst + secondBorrowAmount,
            "Vault balance should have increased by second borrow amount"
        );

        // Final assertions
        // Check that all collateral was supplied to Morpho
        assertEq(
            IERC20(COLLATERAL_TOKEN).balanceOf(address(accessPoint)),
            0,
            "All collateral should have been supplied to Morpho"
        );

        // Check that no loan tokens remain in access point (all bridged to vault)
        assertEq(
            IERC20(LOAN_TOKEN).balanceOf(address(accessPoint)),
            initialLoanBalance,
            "Loan balance shouldn't change in access point (all bridged to vault)"
        );
    }

    function testLendAndBorrowThenPreLiquidate() public {
        vm.rollFork(334664828);
        deploy();

        // Create high-risk position at maximum LTV to enter pre-liquidation zone
        collateralAmount = 1 ether; // 1 $K

        // Get oracle price to calculate max borrowable amount
        oraclePrice = IOracle(ORACLE).price();
        collateralValueInUSD = collateralAmount * oraclePrice / 1e24;

        // Calculate maximum borrow amount at LLTV (62.5%)
        maxBorrowAmount = collateralValueInUSD * (LLTV - 0.005e18) / 1e18 / 1e12;

        // Deal collateral to the access point
        vm.prank(COLLATERAL_MINTER);
        SuperToken(COLLATERAL_TOKEN).mint(address(accessPoint), collateralAmount);

        // Deal loan token to a bob0 address for later use
        deal(LOAN_TOKEN, bob0, maxBorrowAmount * 2); // Extra funds for the bob0

        // Prepare workflow data for lending and borrowing at max LTV
        IBridger.BridgeData memory data = bridgeData[ARBITRUM_CHAINID][USDC_ARBITRUM];
        bytes memory lendWorkflowData = abi.encodeWithSelector(
            MorphoWorkflow.lendAndBorrow.selector, collateralAmount, maxBorrowAmount, kintoWallet, data
        );

        // Execute the workflow to create a position at max LTV
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), lendWorkflowData);

        // Get market parameters and ID
        marketParams = _getMarketParams();
        marketId = morphoWorkflow.id(marketParams);

        // Verify position was created at max LTV
        Position memory position = IMorpho(MORPHO).position(marketId, address(accessPoint));
        assertTrue(position.collateral > 0, "Collateral not supplied");
        assertTrue(position.borrowShares > 0, "No loan borrowed");

        // Get pre-liquidation contract from the provided address
        address preliquidation = 0xdE616CeEF394f5E05ed8b6cABa83cBBCC60C0640;
        IPreLiquidationFactory factory = IPreLiquidationFactory(PRE_LIQUIDATION_FACTORY);
        assertTrue(factory.isPreLiquidation(preliquidation), "Not a valid pre-liquidation contract");

        // Record position before liquidation
        uint256 initialCollateral = position.collateral;
        uint256 initialBorrowShares = position.borrowShares;

        // Calculate the amount of shares to repay in pre-liquidation
        // Use a small portion of the loan for this test
        uint256 repayShares = initialBorrowShares / 4; // Repay 25% of the loan

        // Switch to the bob0 account to perform the pre-liquidation
        vm.startPrank(bob0);

        // Approve the Morpho contract to use the loan token for repayment
        IERC20(LOAN_TOKEN).approve(preliquidation, type(uint256).max);

        // Perform the pre-liquidation through the pre-liquidation contract
        IPreLiquidation preLiquidation = IPreLiquidation(preliquidation);
        (uint256 seizedCollateral, uint256 repaidAssets) = preLiquidation.preLiquidate(
            address(accessPoint), // borrower (the access point)
            0, // seizedAssets (0 means we're specifying repaidShares instead)
            repayShares, // repaidShares (how much of the loan we want to repay)
            "" // data (no callback needed)
        );
        vm.stopPrank();

        // Verify the bob0 received the collateral
        uint256 liquidatorCollateral = IERC20(COLLATERAL_TOKEN).balanceOf(bob0);
        assertEq(liquidatorCollateral, seizedCollateral, "bob0 didn't receive collateral");

        // Verify the borrower's position was updated
        Position memory positionAfter = IMorpho(MORPHO).position(marketId, address(accessPoint));

        // Verify position health: collateral decreased, borrow share decreased
        assertLt(positionAfter.collateral, initialCollateral, "Collateral should have decreased");
        assertLt(positionAfter.borrowShares, initialBorrowShares, "Borrow shares should have decreased");

        // Verify the amount of seized collateral and repaid assets are reasonable
        assertGt(seizedCollateral, 0, "Should have seized some collateral");
        assertGt(repaidAssets, 0, "Should have repaid some assets");

        // If the liquidation was successful with bonus, the protocol should have applied an incentive factor
        // The pre-liquidation bonus means that the bob0 gets more collateral than would be exactly fair value
        uint256 fairValueCollateral = repaidAssets * 1e12 / oraclePrice * 1e18;
        assertGt(seizedCollateral, fairValueCollateral, "bob0 should receive a bonus");

        // The position should still exist but be healthier
        assertTrue(positionAfter.collateral > 0, "Position should still have collateral");
        assertTrue(positionAfter.borrowShares > 0, "Position should still have debt");
    }
}

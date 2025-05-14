// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";

import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {MorphoWorkflow} from "@kinto-core/access/workflows/MorphoWorkflow.sol";
import {MorphoViewer} from "@kinto-core/access/workflows/MorphoViewer.sol";
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

contract MorphoViewerTest is SignatureHelper, ForkTest, ArtifactsReader, Constants, BridgeDataHelper {
    using stdJson for string;

    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    MorphoWorkflow internal morphoWorkflow;
    MorphoViewer internal morphoViewer;
    MarketParams internal marketParams;
    Id internal marketId;
    uint256 internal collateralAmount;
    uint256 internal borrowAmount;

    // Morpho protocol constants
    address constant MORPHO = 0x6c247b1F6182318877311737BaC0844bAa518F5e;
    address constant LOAN_TOKEN = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC.e on Arbitrum
    address constant COLLATERAL_TOKEN = 0x010700AB046Dd8e92b0e3587842080Df36364ed3; // $K on Arbitrum
    address constant COLLATERAL_MINTER = 0x702BD1AC995Bf22B8B711A1Ce9796bAc9bdd1f1f;
    address constant ORACLE = 0x2964aB84637d4c3CAF0Fd968be1c97D9990de925;
    address constant IRM = 0x66F30587FB8D4206918deb78ecA7d5eBbafD06DA;
    uint256 constant LLTV = 625000000000000000; // 62.5%
    address constant PRE_LIQUIDATION_FACTORY = 0x635c31B5DF1F7EFbCbC07E302335Ef4230758e3d;
    address constant USER = 0x660ad4B5A74130a4796B4d54BC6750Ae93C86e6c;
    uint256 constant WAD = 1e18; // WAD precision (10^18)

    function setUp() public override {
        super.setUp();

        accessRegistry = AccessRegistry(_getChainDeployment("AccessRegistry"));

        deploy();
    }

    function deploy() internal {
        morphoWorkflow = new MorphoWorkflow();
        vm.label(address(morphoWorkflow), "morphoWorkflow");

        morphoViewer = new MorphoViewer();
        vm.label(address(morphoViewer), "morphoViewer");

        vm.prank(accessRegistry.owner());
        accessRegistry.allowWorkflow(address(morphoWorkflow));
    }

    function setUpChain() public virtual override {
        setUpArbitrumFork();
        // Use a recent block
        vm.rollFork(334964267);
    }

    function testMarketInfo() public {
        // Call marketInfo function
        (uint256 totalSupply, uint256 totalBorrow, uint256 borrowRatePerSecond, uint256 supplyRatePerSecond) =
            morphoViewer.marketInfo();

        // Basic validation of returned values
        assertEq(totalSupply, 10349274, "Total supply should be");
        assertEq(totalBorrow, 1000062, "Total borrow should be");
        assertEq(borrowRatePerSecond, 332832198, "Borrow rate per second should be");
        assertEq(supplyRatePerSecond, 32161950, "Supply rate per second should be");
        assertTrue(borrowRatePerSecond > supplyRatePerSecond, "Borrow rate should be");
    }

    function testPosition() public {
        // Call position function
        (uint256 supplyAssets, uint256 borrowAssets, uint256 collateral) = morphoViewer.position(USER);

        // Basic validation of returned values
        assertEq(supplyAssets, 10349274, "Supply assets should be");
        assertEq(borrowAssets, 1000062, "Borrow assets should be");
        assertEq(collateral, 6000000000000000000, "Collateral should be");
    }

    function testCalculateLTV_CurrentPosition() public {
        // Calculate the current LTV and health factor
        (uint256 ltv, uint256 healthFactor) = morphoViewer.calculateLTV(USER, 0, 0);

        assertEq(ltv, 23978323596619544, "LTV should be");
        assertTrue(ltv < LLTV, "LTV should be less than LLTV (62.5%)");

        // Since LTV is below LLTV, health factor should be > WAD
        assertGt(healthFactor, WAD, "Health factor should be greater than 1.0");
        assertEq(healthFactor, 26065208332083410828, "Health factor should match expected value");
    }

    function testCalculateLTV_HypotheticalPosition() public {
        // Calculate hypothetical LTV and health factor if user adds 5 more $K and borrows 3 more USDC.e
        (uint256 ltv, uint256 healthFactor) = morphoViewer.calculateLTV(USER, 5 ether, 3e6);

        assertEq(ltv, 52313909035316912, "LTV should be");
        assertTrue(ltv < LLTV, "LTV should be less than LLTV (62.5%)");

        // Health factor should be > 1.0 as position is still healthy
        assertGt(healthFactor, WAD, "Health factor should be greater than 1.0");

        // With LLTV of 62.5% and LTV of ~52.3%, health factor should be around 1.2
        assertEq(healthFactor, 11947109507302636809, "Health factor should match expected value");
    }
}

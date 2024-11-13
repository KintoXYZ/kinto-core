// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import "@kinto-core/interfaces/bridger/IBridger.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";

import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {AaveRepayWorkflow} from "@kinto-core/access/workflows/AaveRepayWorkflow.sol";

import "@kinto-core-test/fork/const.sol";
import "@kinto-core-test/helpers/UUPSProxy.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/helpers/ArtifactsReader.sol";
import {ForkTest} from "@kinto-core-test/helpers/ForkTest.sol";
import {AccessRegistryHarness} from "@kinto-core-test/harness/AccessRegistryHarness.sol";
import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";
import {IAavePool, IPoolAddressesProvider} from "@kinto-core/interfaces/external/IAavePool.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "forge-std/console2.sol";

contract AaveRepayWorkflowTest is SignatureHelper, ForkTest, ArtifactsReader, Constants {
    using stdJson for string;

    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    AaveRepayWorkflow internal aaveRepayWorkflow;
    IAavePool internal aavePool;

    function setUp() public override {
        super.setUp();

        accessRegistry = AccessRegistry(_getChainDeployment("AccessRegistry"));

        aavePool = IAavePool(IPoolAddressesProvider(ARB_AAVE_POOL_PROVIDER).getPool());

        deploy();
    }

    function deploy() internal {
        accessPoint = accessRegistry.deployFor(address(alice0));
        vm.label(address(accessPoint), "accessPoint");

        aaveRepayWorkflow = new AaveRepayWorkflow(ARB_AAVE_POOL_PROVIDER);
        vm.label(address(aaveRepayWorkflow), "aaveRepayWorkflow");

        vm.prank(accessRegistry.owner());
        accessRegistry.allowWorkflow(address(aaveRepayWorkflow));
    }

    function setUpChain() public virtual override {
        setUpArbitrumFork();
        vm.rollFork(273472816);
    }

    function testRepay_WhenUSDC() public {
        address collateralAsset = WETH_ARBITRUM;
        address repayAsset = USDC_ARBITRUM;
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 100e6; // 100 USDC

        // First supply collateral and borrow
        deal(collateralAsset, address(accessPoint), collateralAmount);
        vm.startPrank(address(accessPoint));
        IERC20(collateralAsset).approve(address(aavePool), collateralAmount);
        aavePool.supply(collateralAsset, collateralAmount, address(accessPoint), 0);
        aavePool.borrow(repayAsset, borrowAmount, 2, 0, address(accessPoint));
        vm.stopPrank();

        // Deal repay amount to access point
        deal(repayAsset, address(accessPoint), borrowAmount);

        // Get initial balances
        uint256 initialRepayBalance = IERC20(repayAsset).balanceOf(address(accessPoint));
        address variableDebtToken = aavePool.getReserveData(repayAsset).variableDebtTokenAddress;
        uint256 initialDebtBalance = IERC20(variableDebtToken).balanceOf(address(accessPoint));

        // Prepare workflow data
        bytes memory workflowData =
            abi.encodeWithSelector(AaveRepayWorkflow.repay.selector, repayAsset, borrowAmount, address(accessPoint));

        // Approve repay asset
        vm.prank(address(accessPoint));
        IERC20(repayAsset).approve(address(aaveRepayWorkflow), borrowAmount);

        // Execute the repay workflow
        vm.prank(alice0);
        bytes memory response = accessPoint.execute(address(aaveRepayWorkflow), workflowData);
        uint256 amountRepaid = abi.decode(response, (uint256));

        // Assert balances changed correctly
        assertEq(
            IERC20(repayAsset).balanceOf(address(accessPoint)),
            initialRepayBalance - borrowAmount,
            "Invalid repay asset balance"
        );
        assertEq(
            IERC20(variableDebtToken).balanceOf(address(accessPoint)),
            initialDebtBalance - borrowAmount,
            "Invalid debt token balance"
        );
        assertEq(amountRepaid, borrowAmount, "Invalid repaid amount");
    }

    function testRepay_WhenMaxAmount() public {
        address collateralAsset = WETH_ARBITRUM;
        address repayAsset = USDC_ARBITRUM;
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 100e6; // 100 USDC

        // First supply collateral and borrow
        deal(collateralAsset, address(accessPoint), collateralAmount);
        vm.startPrank(address(accessPoint));
        IERC20(collateralAsset).approve(address(aavePool), collateralAmount);
        aavePool.supply(collateralAsset, collateralAmount, address(accessPoint), 0);
        aavePool.borrow(repayAsset, borrowAmount, 2, 0, address(accessPoint));
        vm.stopPrank();

        // Deal repay amount to access point
        deal(repayAsset, address(accessPoint), borrowAmount);

        // Get initial balances
        uint256 initialRepayBalance = IERC20(repayAsset).balanceOf(address(accessPoint));
        address variableDebtToken = aavePool.getReserveData(repayAsset).variableDebtTokenAddress;

        // Prepare workflow data with max amount
        bytes memory workflowData = abi.encodeWithSelector(
            AaveRepayWorkflow.repay.selector, repayAsset, type(uint256).max, address(accessPoint)
        );

        // Approve repay asset
        vm.prank(address(accessPoint));
        IERC20(repayAsset).approve(address(aaveRepayWorkflow), borrowAmount);

        // Execute the repay workflow
        vm.prank(alice0);
        bytes memory response = accessPoint.execute(address(aaveRepayWorkflow), workflowData);
        uint256 amountRepaid = abi.decode(response, (uint256));

        // Assert balances changed correctly
        assertEq(
            IERC20(repayAsset).balanceOf(address(accessPoint)),
            initialRepayBalance - borrowAmount,
            "Invalid repay asset balance"
        );
        assertEq(IERC20(variableDebtToken).balanceOf(address(accessPoint)), 0, "Invalid debt token balance");
        assertEq(amountRepaid, borrowAmount, "Invalid repaid amount");
    }
}

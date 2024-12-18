// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";
import {Bridger} from "@kinto-core/bridger/Bridger.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";

import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {AaveBorrowWorkflow} from "@kinto-core/access/workflows/AaveBorrowWorkflow.sol";
import {BridgeDataHelper} from "@kinto-core-test/helpers/BridgeDataHelper.sol";

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

contract AaveBorrowWorkflowTest is SignatureHelper, ForkTest, ArtifactsReader, Constants, BridgeDataHelper {
    using stdJson for string;

    Bridger internal bridger;
    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    AaveBorrowWorkflow internal aaveBorrowWorkflow;
    IAavePool internal aavePool;

    function setUp() public override {
        super.setUp();

        bridger = Bridger(payable(_getChainDeployment("Bridger")));
        accessRegistry = AccessRegistry(_getChainDeployment("AccessRegistry"));

        aavePool = IAavePool(IPoolAddressesProvider(ARB_AAVE_POOL_PROVIDER).getPool());

        deploy();
    }

    function deploy() internal {
        accessPoint = accessRegistry.deployFor(address(alice0));
        vm.label(address(accessPoint), "accessPoint");

        aaveBorrowWorkflow = new AaveBorrowWorkflow(ARB_AAVE_POOL_PROVIDER, address(bridger));
        vm.label(address(aaveBorrowWorkflow), "aaveBorrowWorkflow");

        vm.prank(accessRegistry.owner());
        accessRegistry.allowWorkflow(address(aaveBorrowWorkflow));
    }

    function setUpChain() public virtual override {
        setUpArbitrumFork();
        vm.rollFork(273472816);
    }

    function testBorrow_WhenUSDC() public {
        address collateralAsset = WETH_ARBITRUM;
        address borrowAsset = USDC_ARBITRUM;
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 100e6; // 100 USDC

        // Supply collateral first
        deal(collateralAsset, address(accessPoint), collateralAmount);
        vm.startPrank(address(accessPoint));
        IERC20(collateralAsset).approve(address(aavePool), collateralAmount);
        aavePool.supply(collateralAsset, collateralAmount, address(accessPoint), 0);
        vm.stopPrank();

        // Get initial balances
        uint256 initialBorrowBalance = IERC20(borrowAsset).balanceOf(address(accessPoint));
        address variableDebtToken = aavePool.getReserveData(borrowAsset).variableDebtTokenAddress;
        uint256 initialDebtBalance = IERC20(variableDebtToken).balanceOf(address(accessPoint));

        // Prepare workflow data
        bytes memory workflowData =
            abi.encodeWithSelector(AaveBorrowWorkflow.borrow.selector, borrowAsset, borrowAmount);

        // Execute the borrow workflow
        vm.prank(alice0);
        accessPoint.execute(address(aaveBorrowWorkflow), workflowData);

        // Assert balances changed correctly
        assertEq(
            IERC20(borrowAsset).balanceOf(address(accessPoint)),
            initialBorrowBalance + borrowAmount,
            "Invalid borrowed asset balance"
        );
        assertEq(
            IERC20(variableDebtToken).balanceOf(address(accessPoint)),
            initialDebtBalance + borrowAmount,
            "Invalid debt token balance"
        );
    }

    function testBorrowAndBridge_WhenUSDC() public {
        address collateralAsset = WETH_ARBITRUM;
        address borrowAsset = USDC_ARBITRUM;
        uint256 collateralAmount = 1 ether;
        uint256 borrowAmount = 100e6; // 100 USDC

        // Supply collateral first
        deal(collateralAsset, address(accessPoint), collateralAmount);
        vm.startPrank(address(accessPoint));
        IERC20(collateralAsset).approve(address(aavePool), collateralAmount);
        aavePool.supply(collateralAsset, collateralAmount, address(accessPoint), 0);
        vm.stopPrank();

        IBridger.BridgeData memory bridgeData = bridgeData[block.chainid][USDC_ARBITRUM];

        // Get initial balances
        uint256 initialBorrowBalance = IERC20(borrowAsset).balanceOf(address(accessPoint));
        address variableDebtToken = aavePool.getReserveData(borrowAsset).variableDebtTokenAddress;
        uint256 initialDebtBalance = IERC20(variableDebtToken).balanceOf(address(accessPoint));
        uint256 initialVaultBalance = IERC20(borrowAsset).balanceOf(address(bridgeData.vault));
        uint256 initialBridgerBalance = IERC20(borrowAsset).balanceOf(address(bridger));

        // Prepare workflow data
        bytes memory workflowData = abi.encodeWithSelector(
            AaveBorrowWorkflow.borrowAndBridge.selector, borrowAsset, borrowAmount, alice0, bridgeData
        );

        // Execute the borrow workflow
        vm.prank(alice0);
        accessPoint.execute(address(aaveBorrowWorkflow), workflowData);

        // Assert balances changed correctly
        assertEq(
            IERC20(borrowAsset).balanceOf(address(accessPoint)), initialBorrowBalance, "Invalid borrowed asset balance"
        );
        assertEq(
            IERC20(variableDebtToken).balanceOf(address(accessPoint)),
            initialDebtBalance + borrowAmount,
            "Invalid debt token balance"
        );
        assertEq(IERC20(borrowAsset).balanceOf(address(bridger)), initialBridgerBalance, "Invalid bridger balance");
        assertEq(
            IERC20(borrowAsset).balanceOf(address(bridgeData.vault)),
            initialVaultBalance + borrowAmount,
            "Invalid vault balance"
        );
    }
}

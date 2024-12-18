// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import "@kinto-core/interfaces/bridger/IBridger.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";

import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {AaveWithdrawWorkflow} from "@kinto-core/access/workflows/AaveWithdrawWorkflow.sol";
import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";
import {Bridger} from "@kinto-core/bridger/Bridger.sol";
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

contract AaveWithdrawWorkflowTest is SignatureHelper, ForkTest, ArtifactsReader, Constants, BridgeDataHelper {
    using stdJson for string;

    Bridger internal bridger;
    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    AaveWithdrawWorkflow internal aaveWithdrawWorkflow;
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

        aaveWithdrawWorkflow = new AaveWithdrawWorkflow(ARB_AAVE_POOL_PROVIDER, address(bridger));
        vm.label(address(aaveWithdrawWorkflow), "aaveWithdrawWorkflow");

        vm.prank(accessRegistry.owner());
        accessRegistry.allowWorkflow(address(aaveWithdrawWorkflow));
    }

    function setUpChain() public virtual override {
        setUpArbitrumFork();
        vm.rollFork(273472816);
    }

    function testWithdraw_WhenUSDC() public {
        address assetToWithdraw = USDC_ARBITRUM;
        uint256 amountToWithdraw = 1e6;
        address aToken = aavePool.getReserveData(assetToWithdraw).aTokenAddress;

        // Supply first to have something to withdraw
        deal(assetToWithdraw, address(accessPoint), amountToWithdraw);
        vm.startPrank(address(accessPoint));
        IERC20(assetToWithdraw).approve(address(aavePool), amountToWithdraw);
        aavePool.supply(assetToWithdraw, amountToWithdraw, address(accessPoint), 0);
        vm.stopPrank();

        // Get initial balances
        uint256 initialAccessPointBalance = IERC20(assetToWithdraw).balanceOf(address(accessPoint));
        uint256 initialATokenBalance = IERC20(aToken).balanceOf(address(accessPoint));

        // Prepare workflow data
        bytes memory workflowData =
            abi.encodeWithSelector(AaveWithdrawWorkflow.withdraw.selector, assetToWithdraw, amountToWithdraw);

        // Execute the withdraw workflow
        vm.prank(alice0);
        accessPoint.execute(address(aaveWithdrawWorkflow), workflowData);

        // Assert balances changed correctly
        assertEq(
            IERC20(assetToWithdraw).balanceOf(address(accessPoint)),
            initialAccessPointBalance + amountToWithdraw,
            "Invalid USDC balance"
        );
        assertEq(
            IERC20(aToken).balanceOf(address(accessPoint)),
            initialATokenBalance - amountToWithdraw,
            "Invalid aToken balance"
        );
    }

    function testWithdraw_WhenMaxAmount() public {
        address assetToWithdraw = USDC_ARBITRUM;
        uint256 amountToSupply = 1e6;
        address aToken = aavePool.getReserveData(assetToWithdraw).aTokenAddress;

        // Supply first to have something to withdraw
        deal(assetToWithdraw, address(accessPoint), amountToSupply);
        vm.startPrank(address(accessPoint));
        IERC20(assetToWithdraw).approve(address(aavePool), amountToSupply);
        aavePool.supply(assetToWithdraw, amountToSupply, address(accessPoint), 0);
        vm.stopPrank();

        // Get initial balances
        uint256 initialAccessPointBalance = IERC20(assetToWithdraw).balanceOf(address(accessPoint));

        // Prepare workflow data with max amount
        bytes memory workflowData = abi.encodeWithSelector(
            AaveWithdrawWorkflow.withdraw.selector, assetToWithdraw, type(uint256).max, address(accessPoint)
        );

        // Execute the withdraw workflow
        vm.prank(alice0);
        accessPoint.execute(address(aaveWithdrawWorkflow), workflowData);

        // Assert balances changed correctly
        assertEq(
            IERC20(assetToWithdraw).balanceOf(address(accessPoint)),
            initialAccessPointBalance + amountToSupply,
            "Invalid USDC balance"
        );
        assertEq(IERC20(aToken).balanceOf(address(accessPoint)), 0, "Invalid aToken balance");
    }

    function testWithdrawAndBridge() public {
        address assetToWithdraw = USDC_ARBITRUM;
        uint256 amountToWithdraw = 1e6;
        address aToken = aavePool.getReserveData(assetToWithdraw).aTokenAddress;

        // Supply first to have something to withdraw
        deal(assetToWithdraw, address(accessPoint), amountToWithdraw);
        vm.startPrank(address(accessPoint));
        IERC20(assetToWithdraw).approve(address(aavePool), amountToWithdraw);
        aavePool.supply(assetToWithdraw, amountToWithdraw, address(accessPoint), 0);
        vm.stopPrank();

        IBridger.BridgeData memory bridgeData = bridgeData[block.chainid][USDC_ARBITRUM];

        // Get initial balances
        uint256 initialAccessPointBalance = IERC20(assetToWithdraw).balanceOf(address(accessPoint));
        uint256 initialATokenBalance = IERC20(aToken).balanceOf(address(accessPoint));
        uint256 initialBridgerBalance = IERC20(assetToWithdraw).balanceOf(address(bridger));
        uint256 initialVaultBalance = IERC20(assetToWithdraw).balanceOf(address(bridgeData.vault));

        // Prepare workflow data
        bytes memory workflowData = abi.encodeWithSelector(
            AaveWithdrawWorkflow.withdrawAndBridge.selector, assetToWithdraw, amountToWithdraw, alice0, bridgeData
        );

        // Execute the withdrawAndBridge workflow
        vm.prank(alice0);
        accessPoint.execute(address(aaveWithdrawWorkflow), workflowData);

        // Assert balances changed correctly
        assertEq(
            IERC20(assetToWithdraw).balanceOf(address(accessPoint)),
            initialAccessPointBalance,
            "Invalid access point balance"
        );
        assertEq(
            IERC20(aToken).balanceOf(address(accessPoint)),
            initialATokenBalance - amountToWithdraw,
            "Invalid aToken balance"
        );
        assertEq(IERC20(assetToWithdraw).balanceOf(address(bridger)), initialBridgerBalance, "Invalid bridger balance");
        assertEq(
            IERC20(assetToWithdraw).balanceOf(address(bridgeData.vault)),
            initialVaultBalance + amountToWithdraw,
            "Invalid vault balance"
        );
    }
}

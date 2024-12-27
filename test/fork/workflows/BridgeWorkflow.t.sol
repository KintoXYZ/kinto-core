// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";
import {Bridger} from "@kinto-core/bridger/Bridger.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";

import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {BridgeWorkflow} from "@kinto-core/access/workflows/BridgeWorkflow.sol";
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

contract BridgeWorkflowTest is SignatureHelper, ForkTest, ArtifactsReader, Constants, BridgeDataHelper {
    using stdJson for string;

    Bridger internal bridger;
    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    BridgeWorkflow internal bridgeWorkflow;
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

        bridgeWorkflow = new BridgeWorkflow(bridger);
        vm.label(address(bridgeWorkflow), "bridgeWorkflow");

        vm.prank(accessRegistry.owner());
        accessRegistry.allowWorkflow(address(bridgeWorkflow));
    }

    function setUpChain() public virtual override {
        setUpArbitrumFork();
        vm.rollFork(273472816);
    }

    function testBridge() public {
        address assetIn = USDC_ARBITRUM;
        uint256 amountIn = 100e6; // 100 USDC

        IBridger.BridgeData memory bridgeData = bridgeData[block.chainid][USDC_ARBITRUM];

        // Supply collateral first
        deal(assetIn, address(accessPoint), amountIn);

        // Get initial balances
        uint256 initialBalance = IERC20(assetIn).balanceOf(address(accessPoint));

        // Prepare workflow data
        bytes memory workflowData =
            abi.encodeWithSelector(BridgeWorkflow.bridge.selector, assetIn, amountIn, address(0xdead), bridgeData);

        // Execute the borrow workflow
        vm.prank(alice0);
        accessPoint.execute(address(bridgeWorkflow), workflowData);

        // Assert balances changed correctly
        assertEq(IERC20(assetIn).balanceOf(address(accessPoint)), initialBalance - amountIn, "Invalid asset balance");
    }
}

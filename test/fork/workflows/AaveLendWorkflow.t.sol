// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import "@kinto-core/interfaces/bridger/IBridger.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";

import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {AaveLendWorkflow} from "@kinto-core/access/workflows/AaveLendWorkflow.sol";

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

contract AaveLendWorkflowTest is SignatureHelper, ForkTest, ArtifactsReader, Constants {
    using stdJson for string;

    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    AaveLendWorkflow internal aaveLendWorkflow;
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

        aaveLendWorkflow = new AaveLendWorkflow(ARB_AAVE_POOL_PROVIDER);
        vm.label(address(aaveLendWorkflow), "aaveLendWorkflow");

        vm.prank(accessRegistry.owner());
        accessRegistry.allowWorkflow(address(aaveLendWorkflow));
    }

    function setUpChain() public virtual override {
        setUpArbitrumFork();
        vm.rollFork(273472816);
    }

    function testLend_WhenUSDC() public {
        address assetToLend = USDC_ARBITRUM;
        uint256 amountToLend = 1e6;

        // Get initial balances
        uint256 initialAccessPointBalance = IERC20(assetToLend).balanceOf(address(accessPoint));
        address aToken = aavePool.getReserveData(assetToLend).aTokenAddress;
        uint256 initialATokenBalance = IERC20(aToken).balanceOf(address(accessPoint));

        // Prepare workflow data
        bytes memory workflowData = abi.encodeWithSelector(AaveLendWorkflow.lend.selector, assetToLend, amountToLend);

        // Fund the access point
        deal(assetToLend, address(accessPoint), amountToLend);

        // Execute the lend workflow
        vm.prank(alice0);
        accessPoint.execute(address(aaveLendWorkflow), workflowData);

        // Assert balances changed correctly
        assertEq(IERC20(assetToLend).balanceOf(address(accessPoint)), initialAccessPointBalance, "Invalid USDC balance");
        assertEq(
            IERC20(aToken).balanceOf(address(accessPoint)),
            initialATokenBalance + amountToLend,
            "Invalid aToken balance"
        );
    }

    function testLend_WhenZeroAmount() public {
        address assetToLend = USDC_ARBITRUM;
        uint256 amountToFund = 1e6;

        // Get initial balances
        uint256 initialAccessPointBalance = IERC20(assetToLend).balanceOf(address(accessPoint));
        address aToken = aavePool.getReserveData(assetToLend).aTokenAddress;
        uint256 initialATokenBalance = IERC20(aToken).balanceOf(address(accessPoint));

        // Prepare workflow data with zero amount (should use full balance)
        bytes memory workflowData = abi.encodeWithSelector(AaveLendWorkflow.lend.selector, assetToLend, 0);

        // Fund the access point
        deal(assetToLend, address(accessPoint), amountToFund);

        // Execute the lend workflow
        vm.prank(alice0);
        accessPoint.execute(address(aaveLendWorkflow), workflowData);

        // Assert balances changed correctly
        assertEq(IERC20(assetToLend).balanceOf(address(accessPoint)), initialAccessPointBalance, "Invalid USDC balance");
        assertEq(
            IERC20(aToken).balanceOf(address(accessPoint)),
            initialATokenBalance + amountToFund,
            "Invalid aToken balance"
        );
    }
}

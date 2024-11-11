// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import "@kinto-core/interfaces/bridger/IBridger.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";

import "@kinto-core/bridger/Bridger.sol";
import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {LendAndBridgeWorkflow} from "@kinto-core/access/workflows/LendAndBridgeWorkflow.sol";

import "@kinto-core-test/fork/const.sol";
import "@kinto-core-test/helpers/UUPSProxy.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/harness/BridgerHarness.sol";
import "@kinto-core-test/helpers/ArtifactsReader.sol";
import "@kinto-core-test/helpers/BridgeDataHelper.sol";
import {ForkTest} from "@kinto-core-test/helpers/ForkTest.sol";
import {AccessRegistryHarness} from "@kinto-core-test/harness/AccessRegistryHarness.sol";
import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "@kinto-core/interfaces/bridger/IBridger.sol";
import "@kinto-core/bridger/Bridger.sol";

import "forge-std/console2.sol";

contract LendAndBridgeWorkflowTest is SignatureHelper, ForkTest, ArtifactsReader, BridgeDataHelper {
    using stdJson for string;

    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    LendAndBridgeWorkflow internal lendAndBridgeWorkflow;
    address internal constant kintoWalletL2 = address(33);

    Bridger internal bridger;

    uint256 internal amountIn = 1e18;

    function setUp() public override {
        super.setUp();

        bridger = Bridger(payable(_getChainDeployment("Bridger")));
        accessRegistry = AccessRegistry(_getChainDeployment("AccessRegistry"));

        IBridger.BridgeData memory bridgeData = bridgeData[block.chainid][A_ARB_USDC_ARBITRUM];

        vm.prank(bridger.owner());
        bridger.setBridgeVault(bridgeData.vault, true);

        deploy();
    }

    function deploy() internal {
        accessPoint = accessRegistry.deployFor(address(alice0));
        vm.label(address(accessPoint), "accessPoint");

        lendAndBridgeWorkflow = new LendAndBridgeWorkflow(bridger, ARB_AAVE_POOL_PROVIDER, STATIC_A_TOKEN_FACTORY);
        vm.label(address(lendAndBridgeWorkflow), "lendAndBridgeWorkflow");

        vm.prank(accessRegistry.owner());
        accessRegistry.allowWorkflow(address(lendAndBridgeWorkflow));
    }

    function setUpChain() public virtual override {
        setUpArbitrumFork();
        vm.rollFork(273472816);
    }

    function testLendAndBridge_WhenArbUsdc() public {
        IBridger.BridgeData memory bridgeData = bridgeData[block.chainid][A_ARB_USDC_ARBITRUM];
        address assetToLend = USDC_ARBITRUM;
        address assetToDeposit = A_ARB_USDC_ARBITRUM;
        uint256 amountToLend = 1e6;
        uint256 bridgerBalanceBefore = ERC20(assetToDeposit).balanceOf(address(bridger));
        uint256 vaultBalanceBefore = ERC20(assetToDeposit).balanceOf(address(bridgeData.vault));

        bytes memory workflowData = abi.encodeWithSelector(
            LendAndBridgeWorkflow.lendAndBridge.selector, assetToLend, amountToLend, kintoWalletL2, bridgeData
        );

        deal(assetToLend, address(accessPoint), amountIn);

        vm.prank(bridger.owner());
        bridger.setBridgeVault(bridgeData.vault, true);

        vm.prank(alice0);
        bytes memory response = accessPoint.execute(address(lendAndBridgeWorkflow), workflowData);
        uint256 amountOut = abi.decode(response, (uint256));

        uint256 shares = IERC4626(assetToDeposit).convertToShares(amountToLend);

        assertEq(amountOut, shares, "Invalid amountOut");
        assertEq(
            ERC20(assetToDeposit).balanceOf(address(bridger)), bridgerBalanceBefore, "Invalid balance of the Bridger"
        );
        assertEq(
            ERC20(assetToDeposit).balanceOf(bridgeData.vault),
            vaultBalanceBefore + shares,
            "Invalid balance of the Vault"
        );
    }
}

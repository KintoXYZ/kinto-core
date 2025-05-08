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
import {Id, IMorpho, MarketParams} from "@kinto-core/interfaces/external/IMorpho.sol";

import "@kinto-core-test/fork/const.sol";
import "@kinto-core-test/helpers/UUPSProxy.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/helpers/ArtifactsReader.sol";
import {ForkTest} from "@kinto-core-test/helpers/ForkTest.sol";
import {AccessRegistryHarness} from "@kinto-core-test/harness/AccessRegistryHarness.sol";
import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";
import {SuperToken} from "@kinto-core/tokens/bridged/SuperToken.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "forge-std/console2.sol";

contract MorphoWorkflowTest is SignatureHelper, ForkTest, ArtifactsReader, Constants, BridgeDataHelper {
    using stdJson for string;

    Bridger internal bridger;
    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    MorphoWorkflow internal morphoWorkflow;

    // Morpho protocol constants
    address constant MORPHO = 0x6c247b1F6182318877311737BaC0844bAa518F5e;
    address constant LOAN_TOKEN = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC.e on Arbitrum
    address constant COLLATERAL_TOKEN = 0x010700AB046Dd8e92b0e3587842080Df36364ed3; // $K on Arbitrum
    address constant COLLATERAL_MINTER = 0x702BD1AC995Bf22B8B711A1Ce9796bAc9bdd1f1f;
    address constant ORACLE = 0x2964aB84637d4c3CAF0Fd968be1c97D9990de925;
    address constant IRM = 0x66F30587FB8D4206918deb78ecA7d5eBbafD06DA;
    uint256 constant LLTV = 625000000000000000; // 62.5%

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
        uint256 collateralAmount = 10 ether; // 10 $K
        uint256 borrowAmount = 5e6; // 5 USDC.e

        // Deal collateral to the access point
        vm.prank(COLLATERAL_MINTER);
        SuperToken(COLLATERAL_TOKEN).mint(address(accessPoint), collateralAmount);

        // Get initial balances
        uint256 initialCollateralBalance = IERC20(COLLATERAL_TOKEN).balanceOf(address(accessPoint));
        uint256 initialLoanBalance = IERC20(LOAN_TOKEN).balanceOf(address(accessPoint));

        // Prepare workflow data
        bytes memory workflowData =
            abi.encodeWithSelector(MorphoWorkflow.lendAndBorrow.selector, collateralAmount, borrowAmount);

        // Execute the workflow
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), workflowData);

        // Check that collateral was supplied
        assertLt(
            IERC20(COLLATERAL_TOKEN).balanceOf(address(accessPoint)),
            initialCollateralBalance,
            "Collateral balance should have decreased"
        );

        // Check that loan was received
        assertGt(
            IERC20(LOAN_TOKEN).balanceOf(address(accessPoint)), initialLoanBalance, "Loan balance should have increased"
        );
    }

    function testRepayAndWithdraw() public {
        // First, lend and borrow
        uint256 collateralAmount = 10 ether; // 10 $K
        uint256 borrowAmount = 5e6; // 5 USDC.e

        // Mint collateral to the access point
        vm.prank(COLLATERAL_MINTER);
        SuperToken(COLLATERAL_TOKEN).mint(address(accessPoint), collateralAmount);

        // Deal some loan tokens for repayment (use a different approach for USDC.e)
        deal(LOAN_TOKEN, address(accessPoint), borrowAmount);

        // Execute lend and borrow first
        bytes memory lendWorkflowData =
            abi.encodeWithSelector(MorphoWorkflow.lendAndBorrow.selector, collateralAmount, borrowAmount);
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), lendWorkflowData);

        // Get balances after lend/borrow
        uint256 collateralBalance = IERC20(COLLATERAL_TOKEN).balanceOf(address(accessPoint));
        uint256 loanBalance = IERC20(LOAN_TOKEN).balanceOf(address(accessPoint));

        // Prepare repay and withdraw workflow data
        bytes memory repayWorkflowData =
            abi.encodeWithSelector(MorphoWorkflow.repayAndWithdraw.selector, borrowAmount, collateralAmount / 2);

        // Execute the repay workflow
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), repayWorkflowData);

        // Check that loan was repaid
        assertLt(IERC20(LOAN_TOKEN).balanceOf(address(accessPoint)), loanBalance, "Loan balance should have decreased");

        // Check that collateral was partially withdrawn
        assertGt(
            IERC20(COLLATERAL_TOKEN).balanceOf(address(accessPoint)),
            collateralBalance,
            "Collateral balance should have increased"
        );
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
        // First, supply some tokens
        uint256 supplyAmount = 10e6; // 10 USDC

        // Mint tokens to the access point
        deal(LOAN_TOKEN, address(accessPoint), supplyAmount);

        // Supply tokens first
        bytes memory supplyWorkflowData = abi.encodeWithSelector(MorphoWorkflow.supply.selector, supplyAmount);
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), supplyWorkflowData);

        // Get balance after supply
        uint256 balanceAfterSupply = IERC20(LOAN_TOKEN).balanceOf(address(accessPoint));

        // Prepare withdraw workflow data (withdraw half)
        bytes memory withdrawWorkflowData = abi.encodeWithSelector(MorphoWorkflow.withdraw.selector, supplyAmount / 2);

        // Execute the withdraw workflow
        vm.prank(alice0);
        accessPoint.execute(address(morphoWorkflow), withdrawWorkflowData);

        // Check that tokens were withdrawn
        assertGt(
            IERC20(LOAN_TOKEN).balanceOf(address(accessPoint)), balanceAfterSupply, "Balance should have increased"
        );
    }
}

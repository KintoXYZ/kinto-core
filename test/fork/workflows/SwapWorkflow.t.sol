// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin-5.0.1/contracts/utils/cryptography/ECDSA.sol";
import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {MessageHashUtils} from "@openzeppelin-5.0.1/contracts/utils/cryptography/MessageHashUtils.sol";
import {IEntryPoint} from "@aa-v7/interfaces/IEntryPoint.sol";

import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {AccessPoint} from "@kinto-core/access/AccessPoint.sol";
import {SwapWorkflow} from "@kinto-core/access/workflows/SwapWorkflow.sol";
import {WethWorkflow} from "@kinto-core/access/workflows/WethWorkflow.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";

import {AccessRegistryHarness} from "@kinto-core-test/harness/AccessRegistryHarness.sol";

import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {ForkTest} from "@kinto-core-test/helpers/ForkTest.sol";

contract SwapWorkflowTest is ForkTest {
    using MessageHashUtils for bytes32;
    using stdJson for string;

    address payable user = payable(makeAddr("user"));

    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    SwapWorkflow internal swapWorkflow;
    WethWorkflow internal wethWorkflow;

    address payable internal constant ENTRY_POINT = payable(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    address internal constant EXCHANGE_PROXY = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function setUp() public override {
        super.setUp();

        deploy();

        vm.label(EXCHANGE_PROXY, "EXCHANGE_PROXY");
    }

    function setUpChain() public virtual override {
        setUpEthereumFork();
    }

    function deploy() internal {
        // use random address for access point implementation to avoid circular dependency
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(this), address(this));
        IAccessRegistry accessRegistryImpl = new AccessRegistryHarness(beacon);
        UUPSProxy accessRegistryProxy = new UUPSProxy{salt: 0}(address(accessRegistryImpl), "");

        accessRegistry = AccessRegistry(address(accessRegistryProxy));
        beacon.transferOwnership(address(accessRegistry));
        IAccessPoint accessPointImpl = new AccessPoint(IEntryPoint(ENTRY_POINT), accessRegistry);

        accessRegistry.initialize();
        accessRegistry.upgradeAll(accessPointImpl);
        accessPoint = accessRegistry.deployFor(address(user));
        vm.label(address(accessPoint), "accessPoint");

        swapWorkflow = new SwapWorkflow(EXCHANGE_PROXY);
        wethWorkflow = new WethWorkflow(address(WETH));

        accessRegistry.allowWorkflow(address(swapWorkflow));
        accessRegistry.allowWorkflow(address(wethWorkflow));
    }

    function testSwapERC20() public {
        uint256 expectedAmountOut = 999842220668049737510;
        uint256 amountIn = 1e3 * 1e6;
        // block number in which the 0x API data was fetched
        vm.rollFork(19725885);
        deploy();

        // Run to regenerate
        // curl 'https://api.0x.org/swap/v1/quote?buyToken=0x6B175474E89094C44Da98b954EedeAC495271d0F&sellToken=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48&sellAmount=1000000000' --header '0x-api-key: KEY' | jq > ./test/data/swap-quote.json
        string memory quote = vm.readFile("./test/data/swap-quote.json");
        bytes memory swapCallData = quote.readBytes(".data");
        bytes memory data = abi.encodeWithSelector(SwapWorkflow.fillQuote.selector, USDC, amountIn, DAI, swapCallData);

        deal(USDC, address(accessPoint), amountIn);

        vm.expectEmit();
        emit SwapWorkflow.SwapExecuted(USDC, amountIn, DAI, expectedAmountOut);

        vm.prank(user);
        bytes memory response = accessPoint.execute(address(swapWorkflow), data);
        uint256 amountOut = abi.decode(response, (uint256));

        // check that swap is executed
        assertEq(IERC20(USDC).balanceOf(address(accessPoint)), 0, "USDC balance is wrong");
        assertEq(IERC20(DAI).balanceOf(address(accessPoint)), expectedAmountOut, "DAI balance is wrong");
        assertEq(amountOut, expectedAmountOut, "AmountOut is wrong");
    }

    function testSwapNative() public {
        uint256 expectedAmountOut = 3151957905853340218861;
        uint256 amountIn = 1e18;

        // block number in which the 0x API data was fetched
        vm.rollFork(19734091);
        deploy();

        // deal ETH
        deal(address(accessPoint), amountIn);
        // wrap ETH to WETH
        bytes memory data = abi.encodeWithSelector(WethWorkflow.deposit.selector, amountIn);
        vm.prank(user);
        accessPoint.execute(address(wethWorkflow), data);

        // Run to regenerate
        // curl curl 'https://api.0x.org/swap/v1/quote?buyToken=0x6B175474E89094C44Da98b954EedeAC495271d0F&sellToken=0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2&sellAmount=1000000000' --header '0x-api-key: KEY' | jq > ./test/data/swap-weth-quote.json
        string memory quote = vm.readFile("./test/data/swap-weth-quote.json");
        bytes memory swapCallData = quote.readBytes(".data");
        data = abi.encodeWithSelector(SwapWorkflow.fillQuote.selector, IERC20(WETH), amountIn, DAI, swapCallData);

        vm.prank(user);
        bytes memory response = accessPoint.execute(address(swapWorkflow), data);
        uint256 amountOut = abi.decode(response, (uint256));

        // check that swap is executed
        assertEq(IERC20(WETH).balanceOf(address(accessPoint)), 0, "USDC balance is wrong");
        assertEq(IERC20(DAI).balanceOf(address(accessPoint)), expectedAmountOut, "DAI balance is wrong");
        assertEq(amountOut, expectedAmountOut, "AmountOut is wrong");
    }
}

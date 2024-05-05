// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import {SharedSetup} from "@kinto-core-test/SharedSetup.t.sol";

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin-5.0.1/contracts/utils/cryptography/ECDSA.sol";
import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {MessageHashUtils} from "@openzeppelin-5.0.1/contracts/utils/cryptography/MessageHashUtils.sol";
import {EntryPoint} from "@aa/core/EntryPoint.sol";
import {UserOperation} from "@aa/interfaces/UserOperation.sol";
import {IWETH9 as IWETH} from "@token-bridge-contracts/contracts/tokenbridge/libraries/IWETH9.sol";

import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {AccessPoint} from "@kinto-core/access/AccessPoint.sol";
import {WethWorkflow} from "@kinto-core/access/workflows/WethWorkflow.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";
import {IKintoEntryPoint} from "@kinto-core/interfaces/IKintoEntryPoint.sol";
import {SignaturePaymaster} from "@kinto-core/paymasters/SignaturePaymaster.sol";

import {AccessRegistryHarness} from "@kinto-core-test/harness/AccessRegistryHarness.sol";

import {UserOp} from "@kinto-core-test/helpers/UserOp.sol";
import {ERC20Mock} from "@kinto-core-test/helpers/ERC20Mock.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

contract WethWorkflowTest is UserOp, SharedSetup {
    IKintoEntryPoint entryPoint;
    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    WethWorkflow internal wethWorkflow;

    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    function setUp() public override {
        super.setUp();

        string memory rpc = vm.envString("ETHEREUM_RPC_URL");
        require(bytes(rpc).length > 0, "ETHEREUM_RPC_URL is not set");

        vm.chainId(1);
        mainnetFork = vm.createFork(rpc);
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);

        vm.deal(_owner, 100 ether);

        entryPoint = IKintoEntryPoint(address(new EntryPoint{salt: 0}()));

        // use random address for access point implementation to avoid circular dependency
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(this), address(this));
        IAccessRegistry accessRegistryImpl = new AccessRegistryHarness(beacon);
        UUPSProxy accessRegistryProxy = new UUPSProxy{salt: 0}(address(accessRegistryImpl), "");

        accessRegistry = AccessRegistry(address(accessRegistryProxy));
        beacon.transferOwnership(address(accessRegistry));
        IAccessPoint accessPointImpl = new AccessPoint(entryPoint, accessRegistry);

        accessRegistry.initialize();
        accessRegistry.upgradeAll(accessPointImpl);
        accessPoint = accessRegistry.deployFor(address(_user));
        vm.label(address(accessPoint), "accessPoint");

        wethWorkflow = new WethWorkflow(address(WETH));

        entryPoint.setWalletFactory(address(accessRegistry));
        accessRegistry.allowWorkflow(address(wethWorkflow));
    }

    function testUp() public override {
        WethWorkflow workflow = new WethWorkflow(address(WETH));
        assertEq(address(workflow.weth()), address(WETH));
    }

    function testDeposit() public {
        uint256 amount = 1e18;
        bytes memory data = abi.encodeWithSelector(WethWorkflow.deposit.selector, amount);

        deal(address(accessPoint), amount);
        assertEq(address(accessPoint).balance, amount, "Balance is wrong");
        vm.prank(_user);
        accessPoint.execute(address(wethWorkflow), data);

        // check that WETH is deposited
        assertEq(IERC20(address(WETH)).balanceOf(address(accessPoint)), amount, "WETH balance is wrong");
        assertEq(address(accessPoint).balance, 0, "Balance is wrong");
    }

    function testWithdraw() public {
        uint256 amount = 1e18;
        bytes memory data = abi.encodeWithSelector(WethWorkflow.withdraw.selector, amount);

        deal(address(WETH), address(accessPoint), amount);
        assertEq(address(accessPoint).balance, 0, "Balance is wrong");
        vm.prank(_user);
        accessPoint.execute(address(wethWorkflow), data);

        // check that WETH is withdrawn
        assertEq(IERC20(address(WETH)).balanceOf(address(accessPoint)), 0, "WETH balance is wrong");
        assertEq(address(accessPoint).balance, amount, "Balance is wrong");
    }
}

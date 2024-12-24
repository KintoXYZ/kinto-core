// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin-5.0.1/contracts/utils/cryptography/ECDSA.sol";
import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {MessageHashUtils} from "@openzeppelin-5.0.1/contracts/utils/cryptography/MessageHashUtils.sol";

import {PackedUserOperation} from "@aa-v7/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "@aa-v7/interfaces/IEntryPoint.sol";

import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {AccessPoint} from "@kinto-core/access/AccessPoint.sol";
import {WithdrawWorkflow} from "@kinto-core/access/workflows/WithdrawWorkflow.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";

import {AccessRegistryHarness} from "@kinto-core-test/harness/AccessRegistryHarness.sol";
import {BaseTest} from "@kinto-core-test/helpers/BaseTest.sol";
import {ERC20Mock} from "@kinto-core-test/helpers/ERC20Mock.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

import {WETH} from "@kinto-core-test/helpers/WETH.sol";

contract WithdrawWorkflowTest is BaseTest {
    using MessageHashUtils for bytes32;

    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    WithdrawWorkflow internal withdrawWorkflow;
    ERC20Mock internal token;

    uint48 internal validUntil = 2;
    uint48 internal validAfter = 0;

    uint256 internal defaultAmount = 1e3 * 1e18;
    address internal weth;

    address payable internal constant ENTRY_POINT = payable(0x0000000071727De22E5E9d8BAf0edAc6f37da032);

    function setUp() public override {
        vm.deal(_owner, 100 ether);
        token = new ERC20Mock("Token", "TNK", 18);
        weth = address(new WETH());

        // use random address for access point implementation to avoid circular dependency
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(this), address(this));
        IAccessRegistry accessRegistryImpl = new AccessRegistryHarness(beacon);
        UUPSProxy accessRegistryProxy = new UUPSProxy{salt: 0}(address(accessRegistryImpl), "");

        accessRegistry = AccessRegistry(address(accessRegistryProxy));
        beacon.transferOwnership(address(accessRegistry));
        IAccessPoint accessPointImpl = new AccessPoint(IEntryPoint(ENTRY_POINT), accessRegistry);

        accessRegistry.initialize();
        accessRegistry.upgradeAll(accessPointImpl);
        accessPoint = accessRegistry.deployFor(address(_user));

        withdrawWorkflow = new WithdrawWorkflow(weth);

        accessRegistry.allowWorkflow(address(withdrawWorkflow));
    }

    function testWithdrawERC20() public {
        token.mint(address(accessPoint), defaultAmount);

        bytes memory data =
            abi.encodeWithSelector(WithdrawWorkflow.withdrawERC20.selector, IERC20(token), defaultAmount);

        vm.prank(_user);
        accessPoint.execute(address(withdrawWorkflow), data);

        assertEq(token.balanceOf(_user), defaultAmount);
    }

    function testWithdrawERC20__WhenAmountMax() public {
        token.mint(address(accessPoint), defaultAmount);

        bytes memory data =
            abi.encodeWithSelector(WithdrawWorkflow.withdrawERC20.selector, IERC20(token), type(uint256).max);

        vm.prank(_user);
        accessPoint.execute(address(withdrawWorkflow), data);

        assertEq(token.balanceOf(_user), defaultAmount);
    }

    function testWithdrawNative() public {
        vm.deal(address(accessPoint), defaultAmount);

        bytes memory data = abi.encodeWithSelector(WithdrawWorkflow.withdrawNative.selector, defaultAmount);

        vm.prank(_user);
        accessPoint.execute(address(withdrawWorkflow), data);

        assertEq(_user.balance, defaultAmount);
    }

    function testWithdrawNative__WhenFromWeth() public {
        // Mint WETH to the access point by depositing ETH
        vm.deal(address(accessPoint), defaultAmount);
        vm.prank(address(accessPoint));
        WETH(weth).deposit{value: defaultAmount}();

        // Execute withdrawal
        bytes memory data = abi.encodeWithSelector(WithdrawWorkflow.withdrawNative.selector, defaultAmount);

        vm.prank(_user);
        accessPoint.execute(address(withdrawWorkflow), data);

        assertEq(_user.balance, defaultAmount);
    }

    function testWithdrawNative__RevertWhenInsufficientBalance() public {
        // Ensure both native and WETH balances are 0
        assertEq(address(accessPoint).balance, 0);
        assertEq(IERC20(weth).balanceOf(address(accessPoint)), 0);

        bytes memory data = abi.encodeWithSelector(WithdrawWorkflow.withdrawNative.selector, defaultAmount);

        vm.prank(_user);
        vm.expectRevert(WithdrawWorkflow.NativeWithdrawalFailed.selector);
        accessPoint.execute(address(withdrawWorkflow), data);
    }

    function testWithdrawNative_MaxAmount() public {
        uint256 nativeAmount = 1 ether;
        uint256 wethAmount = 2 ether;

        // Fund with both native ETH and WETH
        vm.deal(address(accessPoint), nativeAmount + wethAmount);
        vm.prank(address(accessPoint));
        WETH(weth).deposit{value: wethAmount}();

        bytes memory data = abi.encodeWithSelector(WithdrawWorkflow.withdrawNative.selector, type(uint256).max);

        vm.prank(_user);
        accessPoint.execute(address(withdrawWorkflow), data);

        // Should receive total of native + weth amounts
        assertEq(_user.balance, nativeAmount + wethAmount);
        assertEq(IERC20(weth).balanceOf(address(accessPoint)), 0);
    }

    function testWithdrawNative_MaxAmount_OnlyWETH() public {
        uint256 wethAmount = 2 ether;

        // Fund with only WETH
        vm.deal(address(accessPoint), wethAmount);
        vm.prank(address(accessPoint));
        WETH(weth).deposit{value: wethAmount}();

        bytes memory data = abi.encodeWithSelector(WithdrawWorkflow.withdrawNative.selector, type(uint256).max);

        vm.prank(_user);
        accessPoint.execute(address(withdrawWorkflow), data);

        assertEq(_user.balance, wethAmount);
        assertEq(IERC20(weth).balanceOf(address(accessPoint)), 0);
    }

    function testWithdrawNative_MaxAmount_OnlyNative() public {
        uint256 nativeAmount = 1 ether;

        // Fund with only native ETH
        vm.deal(address(accessPoint), nativeAmount);

        bytes memory data = abi.encodeWithSelector(WithdrawWorkflow.withdrawNative.selector, type(uint256).max);

        vm.prank(_user);
        accessPoint.execute(address(withdrawWorkflow), data);

        assertEq(_user.balance, nativeAmount);
    }
}

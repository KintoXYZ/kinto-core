// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Permit} from "@openzeppelin-5.0.1/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin-5.0.1/contracts/utils/cryptography/ECDSA.sol";
import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {MessageHashUtils} from "@openzeppelin-5.0.1/contracts/utils/cryptography/MessageHashUtils.sol";

import {PackedUserOperation} from "@aa-v7/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "@aa-v7/interfaces/IEntryPoint.sol";
import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";

import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {AccessPoint} from "@kinto-core/access/AccessPoint.sol";
import {BridgeWorkflow} from "@kinto-core/access/workflows/BridgeWorkflow.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";

import {AccessRegistryHarness} from "@kinto-core-test/harness/AccessRegistryHarness.sol";
import {BaseTest} from "@kinto-core-test/helpers/BaseTest.sol";
import {ERC20Mock} from "@kinto-core-test/helpers/ERC20Mock.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

import {IBridge} from "@kinto-core/interfaces/bridger/IBridge.sol";
import {BridgerHarness} from "@kinto-core-test/harness/BridgerHarness.sol";
import {BridgeMock} from "@kinto-core-test/mock/BridgeMock.sol";
import {WETH} from "@kinto-core-test/helpers/WETH.sol";

contract BridgeWorkflowTest is BaseTest {
    using MessageHashUtils for bytes32;

    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    BridgeWorkflow internal bridgeWorkflow;
    ERC20Mock internal token;
    IBridger.BridgeData internal mockBridgerData;
    IBridge internal vault;
    BridgerHarness internal bridger;

    address internal dai;
    address internal connector;
    address internal senderAccount;
    address internal router;
    address internal weth;
    address internal usde;
    address internal wstEth;

    bytes internal constant EXEC_PAYLOAD = bytes("EXEC_PAYLOAD");
    bytes internal constant OPTIONS = bytes("OPTIONS");

    uint256 internal constant MSG_GAS_LIMIT = 1e6;
    uint256 internal constant GAS_FEE = 1e16;

    uint256 internal defaultAmount = 1e3 * 1e18;

    address payable internal constant ENTRY_POINT = payable(0x0000000071727De22E5E9d8BAf0edAc6f37da032);

    function setUp() public override {
        vm.deal(_owner, 100 ether);
        token = new ERC20Mock("Token", "TNK", 18);

        vault = new BridgeMock(address(token));

        dai = makeAddr("dai");
        senderAccount = makeAddr("sender");
        connector = makeAddr("connector");
        router = makeAddr("router");
        weth = address(new WETH());
        usde = makeAddr("usde");
        wstEth = makeAddr("wsteth");

        // deploy a new Bridger contract
        BridgerHarness implementation = new BridgerHarness(router, address(0), weth, dai, usde, address(0), wstEth);
        address proxy = address(new UUPSProxy{salt: 0}(address(implementation), ""));
        bridger = BridgerHarness(payable(proxy));
        vm.label(address(bridger), "bridger");

        vm.prank(_owner);
        bridger.initialize(senderAccount);

        vm.prank(_owner);
        bridger.setBridgeVault(address(vault), true);

        mockBridgerData = IBridger.BridgeData({
            vault: address(vault),
            gasFee: GAS_FEE,
            msgGasLimit: MSG_GAS_LIMIT,
            connector: connector,
            execPayload: EXEC_PAYLOAD,
            options: OPTIONS
        });

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

        bridgeWorkflow = new BridgeWorkflow(bridger);

        accessRegistry.allowWorkflow(address(bridgeWorkflow));
    }

    function testBridge() public {
        vm.deal(_user, 100 ether);

        token.mint(address(accessPoint), defaultAmount);

        bytes memory data = abi.encodeWithSelector(
            BridgeWorkflow.bridge.selector, IERC20(token), defaultAmount, address(0xdead), mockBridgerData
        );

        vm.prank(_user);
        vm.expectEmit(true, true, true, true);
        emit BridgeWorkflow.Bridged(address(0xdead), address(token), defaultAmount);
        vm.expectCall(
            address(vault),
            GAS_FEE,
            abi.encodeCall(
                vault.bridge, (address(0xdead), defaultAmount, MSG_GAS_LIMIT, connector, EXEC_PAYLOAD, OPTIONS)
            )
        );
        accessPoint.execute{value: GAS_FEE}(address(bridgeWorkflow), data);

        assertEq(token.balanceOf(address(accessPoint)), 0);
        assertEq(token.balanceOf(address(vault)), defaultAmount);
    }

    function testBridgeWhenAmountIsZero() public {
        vm.deal(_user, 100 ether);

        token.mint(address(accessPoint), defaultAmount);

        bytes memory data =
            abi.encodeWithSelector(BridgeWorkflow.bridge.selector, IERC20(token), 0, address(0xdead), mockBridgerData);

        vm.prank(_user);
        accessPoint.execute{value: GAS_FEE}(address(bridgeWorkflow), data);

        assertEq(token.balanceOf(address(accessPoint)), 0);
        assertEq(token.balanceOf(address(vault)), defaultAmount);
    }

    function testBridge_RevertWhenInvalidVault() public {
        vm.prank(_owner);
        bridger.setBridgeVault(address(vault), false);

        vm.deal(_user, 100 ether);

        token.mint(address(accessPoint), defaultAmount);

        bytes memory data = abi.encodeWithSelector(
            BridgeWorkflow.bridge.selector, IERC20(token), defaultAmount, address(0xdead), mockBridgerData
        );

        vm.prank(_user);
        vm.expectRevert(abi.encodeWithSelector(IBridger.InvalidVault.selector, address(vault)));
        accessPoint.execute{value: GAS_FEE}(address(bridgeWorkflow), data);
    }
}

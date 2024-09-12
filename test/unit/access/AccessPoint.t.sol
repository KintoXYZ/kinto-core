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
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";

import {AccessRegistryHarness} from "@kinto-core-test/harness/AccessRegistryHarness.sol";
import {BaseTest} from "@kinto-core-test/helpers/BaseTest.sol";
import {ERC20Mock} from "@kinto-core-test/helpers/ERC20Mock.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

import {IBridge} from "@kinto-core/interfaces/bridger/IBridge.sol";
import {BridgerHarness} from "@kinto-core-test/harness/BridgerHarness.sol";
import {BridgeMock} from "@kinto-core-test/mock/BridgeMock.sol";
import {WorkflowMock} from "@kinto-core-test/mock/WorkflowMock.sol";
import {WETH} from "@kinto-core-test/helpers/WETH.sol";

contract AccessPointTest is BaseTest {
    using MessageHashUtils for bytes32;

    AccessRegistry internal accessRegistry;
    IAccessPoint internal accessPoint;
    ERC20Mock internal token;
    address payable internal constant ENTRY_POINT = payable(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    WorkflowMock internal workflowMock;

    function setUp() public override {
        vm.deal(_owner, 100 ether);
        token = new ERC20Mock("Token", "TNK", 18);

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

        workflowMock = new WorkflowMock();

        accessRegistry.allowWorkflow(address(workflowMock));
    }

    function testExecuteBatch() public {
        vm.deal(_user, 100 ether);

        address[] memory target = new address[](2);
        target[0] = address(workflowMock);
        target[1] = address(workflowMock);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(WorkflowMock.answer.selector);
        data[1] = abi.encodeWithSelector(WorkflowMock.answer.selector);

        vm.prank(_user);
        accessPoint.executeBatch(target, data);
    }
}

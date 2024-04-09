// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin-5.0.1/contracts/utils/cryptography/ECDSA.sol";
import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {EntryPoint} from "@aa/core/EntryPoint.sol";

import {AccessRegistry} from "../src/access/AccessRegistry.sol";
import {AccessPoint} from "../src/access/AccessPoint.sol";
import {WithdrawWorkflow} from "../src/access/workflows/WithdrawWorkflow.sol";
import {IAccessPoint} from "../src/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "../src/interfaces/IAccessRegistry.sol";
import {IKintoEntryPoint} from "../src/interfaces/IKintoEntryPoint.sol";
import {SignaturePaymaster} from "../src/paymasters/SignaturePaymaster.sol";

import {AccessRegistryHarness} from "./harness/AccessRegistryHarness.sol";

import {UserOp} from "./helpers/UserOp.sol";
import {ERC20Mock} from "./helpers/ERC20Mock.sol";
import {UUPSProxy} from "./helpers/UUPSProxy.sol";

contract AccessRegistryTest is UserOp {
    using ECDSA for bytes32;

    IKintoEntryPoint entryPoint;
    AccessRegistry internal accessRegistry;
    ERC20Mock internal token;
    address internal workflow = address(0xdead);

    uint48 internal validUntil = 0xdeadbeef;
    uint48 internal validAfter = 1234;

    uint256 internal defaultAmount = 1e3 * 1e18;

    function setUp() public {
        entryPoint = IKintoEntryPoint(address(new EntryPoint{salt: 0}()));
        // use random address for access point implementation to avoid circular dependency
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(this), address(this));
        IAccessRegistry accessRegistryImpl = new AccessRegistryHarness(beacon);
        UUPSProxy accessRegistryProxy = new UUPSProxy{salt: 0}(address(accessRegistryImpl), "");

        accessRegistry = AccessRegistry(address(accessRegistryProxy));
        beacon.transferOwnership(address(accessRegistry));
        IAccessPoint accessPointImpl = new AccessPoint(entryPoint, accessRegistry);

        vm.prank(_owner);
        accessRegistry.initialize();
        vm.prank(_owner);
        accessRegistry.upgradeAll(accessPointImpl);
    }

    function testAllowWorkflow() public {
        assertEq(accessRegistry.isWorkflowAllowed(workflow), false);

        vm.prank(_owner);
        accessRegistry.allowWorkflow(workflow);

        assertEq(accessRegistry.isWorkflowAllowed(workflow), true);
    }

    function testAllowWorkflow_RevertWhen_AlreadyAllowed() public {
        vm.prank(_owner);
        accessRegistry.allowWorkflow(workflow);

        vm.expectRevert(abi.encodeWithSelector(IAccessRegistry.WorkflowAlreadyAllowed.selector, workflow));
        vm.prank(_owner);
        accessRegistry.allowWorkflow(workflow);
    }

    function testDisallowWorkflow() public {
        vm.prank(_owner);
        accessRegistry.allowWorkflow(workflow);

        assertEq(accessRegistry.isWorkflowAllowed(workflow), true);

        vm.prank(_owner);
        accessRegistry.disallowWorkflow(workflow);

        assertEq(accessRegistry.isWorkflowAllowed(workflow), false);
    }

    function testDisallowWorkflow_RevertWhen_AlreadyDisallowed() public {
        vm.expectRevert(abi.encodeWithSelector(IAccessRegistry.WorkflowAlreadyDisallowed.selector, workflow));
        vm.prank(_owner);
        accessRegistry.disallowWorkflow(workflow);
    }
}

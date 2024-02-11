// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@aa/core/EntryPoint.sol";

import "../src/access/AccessRegistry.sol";
import "../src/access/AccessPoint.sol";
import "../src/access/workflows/WithdrawWorkflow.sol";
import "../src/interfaces/IAccessPoint.sol";
import "../src/interfaces/IKintoEntryPoint.sol";
import "../src/paymasters/SignaturePaymaster.sol";

import "./helpers/UserOp.sol";
import "./helpers/ERC20Mock.sol";
import "./helpers/UUPSProxy.sol";

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
        IAccessRegistry accessRegistryImpl = new AccessRegistry();
        UUPSProxy accessRegistryProxy = new UUPSProxy{salt: 0}(
            address(accessRegistryImpl),
            ""
        );

        accessRegistry = AccessRegistry(address(accessRegistryProxy));
        IAccessPoint accessPointImpl = new AccessPoint(
            entryPoint,
            accessRegistry
        );

        vm.prank(_owner);
        accessRegistry.initialize(accessPointImpl);
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

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessRegistry.WorkflowAlreadyAllowed.selector,
                workflow
            )
        );
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
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessRegistry.WorkflowAlreadyDisallowed.selector,
                workflow
            )
        );
        vm.prank(_owner);
        accessRegistry.disallowWorkflow(workflow);
    }

}

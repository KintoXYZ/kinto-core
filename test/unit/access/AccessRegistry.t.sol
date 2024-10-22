// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ECDSA} from "@openzeppelin-5.0.1/contracts/utils/cryptography/ECDSA.sol";
import {UpgradeableBeacon} from "@openzeppelin-5.0.1/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {EntryPoint} from "@aa-v7/core/EntryPoint.sol";
import {Create2} from "@openzeppelin-5.0.1/contracts/utils/Create2.sol";

import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {AccessPoint} from "@kinto-core/access/AccessPoint.sol";
import {WithdrawWorkflow} from "@kinto-core/access/workflows/WithdrawWorkflow.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";
import {Constants} from "@kinto-core/libraries/Const.sol";

import {AccessRegistryHarness} from "@kinto-core-test/harness/AccessRegistryHarness.sol";

import {BaseTest} from "@kinto-core-test/helpers/BaseTest.sol";
import {ERC20Mock} from "@kinto-core-test/helpers/ERC20Mock.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

contract AccessRegistryTest is BaseTest {
    using ECDSA for bytes32;

    EntryPoint entryPoint;
    AccessRegistry internal accessRegistry;
    address internal workflow = address(0xdead);

    uint48 internal validUntil = 0xdeadbeef;
    uint48 internal validAfter = 1234;

    uint256 internal defaultAmount = 1e3 * 1e18;

    function setUp() public override {
        entryPoint = new EntryPoint{salt: 0}();
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

    function testCreateAccountDuplicate() public {
        address addr = address(accessRegistry.createAccount(_user, 1234));
        assertEq(addr, accessRegistry.getAddress(_user, 4321));

        addr = address(accessRegistry.createAccount(_user, 1234));
        assertEq(addr, accessRegistry.getAddress(_user, 4321));
    }

    function testCreateAccount() public {
        address addr = address(accessRegistry.createAccount(_user, 1234));
        assertEq(addr, accessRegistry.getAddress(_user, 4321));
    }

    function testGetAddress() public view {
        address addr = accessRegistry.getAddress(_user);
        address addrSalt = accessRegistry.getAddress(_user, 1234);

        address expected = Create2.computeAddress(
            bytes32(abi.encodePacked(_user)),
            keccak256(
                abi.encodePacked(
                    Constants.safeBeaconProxyCreationCode,
                    abi.encode(address(accessRegistry.beacon()), abi.encodeCall(IAccessPoint.initialize, (_user)))
                )
            ),
            address(accessRegistry)
        );

        assertEq(addr, addrSalt);
        assertEq(addr, expected);
    }
}

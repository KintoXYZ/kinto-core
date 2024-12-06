// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AccessRegistry} from "@kinto-core/access/AccessRegistry.sol";
import {AccessPoint} from "@kinto-core/access/AccessPoint.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";
import {UUPSUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";
import {IEntryPoint} from "@aa-v7/interfaces/IEntryPoint.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/console2.sol";

contract DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        AccessManager accessManager = AccessManager(_getChainDeployment("AccessManager"));
        AccessRegistry accessRegistry = AccessRegistry(_getChainDeployment("AccessRegistry"));
        address safe = getMamoriSafeByChainId(block.chainid);
        console2.log("safe:", safe);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = AccessRegistry.upgradeAll.selector;
        selectors[1] = UUPSUpgradeable.upgradeToAndCall.selector;
        selectors[2] = AccessRegistry.disallowWorkflow.selector;
        selectors[3] = AccessRegistry.allowWorkflow.selector;

        vm.startBroadcast(deployerPrivateKey);

        // make Safe an admin
        accessManager.grantRole(accessManager.ADMIN_ROLE(), safe, 0);

        // set UPGRADER role for target functions
        accessManager.setTargetFunctionRole(address(accessRegistry), selectors, UPGRADER_ROLE);

        // label the role
        accessManager.labelRole(UPGRADER_ROLE, "UPGRADER_ROLE");

        // grant role to a Safe with a delay
        accessManager.grantRole(UPGRADER_ROLE, safe, ACCESS_REGISTRY_DELAY);

        // set grantDelay, so admin can't grant the same role to another account with no delay
        accessManager.setGrantDelay(UPGRADER_ROLE, ACCESS_REGISTRY_DELAY);

        // set delay on admin actions so admin can't move selectors to another role with no delay
        accessManager.setTargetAdminDelay(address(accessRegistry), ACCESS_REGISTRY_DELAY);

        // transfer ownership to access manager
        accessRegistry.transferOwnership(address(accessManager));

        vm.stopBroadcast();

        assertEq(accessRegistry.owner(), address(accessManager));

        // check that Safe is an admin
        (bool isMember, uint32 currentDelay) = accessManager.hasRole(accessManager.ADMIN_ROLE(), safe);
        assertTrue(isMember);
        assertEq(currentDelay, 0);

        (bool immediate, uint32 delay) =
            accessManager.canCall(safe, address(accessRegistry), AccessRegistry.upgradeAll.selector);
        assertFalse(immediate);
        assertEq(delay, ACCESS_REGISTRY_DELAY);

        (isMember, currentDelay) = accessManager.hasRole(UPGRADER_ROLE, safe);
        assertTrue(isMember);
        assertEq(currentDelay, ACCESS_REGISTRY_DELAY);

        // test that we can upgrade to a new access point version
        AccessPoint newImpl = new AccessPoint(IEntryPoint(ENTRY_POINT), accessRegistry);

        bytes memory upgradeAllCalldata = abi.encodeWithSelector(AccessRegistry.upgradeAll.selector, newImpl);

        vm.prank(safe);
        accessManager.schedule(
            address(accessRegistry), upgradeAllCalldata, uint48(block.timestamp + ACCESS_REGISTRY_DELAY)
        );

        vm.warp(block.timestamp + ACCESS_REGISTRY_DELAY);

        vm.prank(safe);
        accessManager.execute(address(accessRegistry), upgradeAllCalldata);

        assertEq(address(newImpl), accessRegistry.beacon().implementation());
    }
}

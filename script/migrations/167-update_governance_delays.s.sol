// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";
import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";
import {KintoID} from "@kinto-core/KintoID.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/console2.sol";

/**
 * @title Update governance settings
 * @notice This script:
 * 1. Updates execution delays in AccessManager from 7 to 11 days
 * 2. Removes GOVERNANCE_ROLE from NioGovernor so only SecurityCouncil can call confirmSanction()
 */
contract DeployScript is MigrationHelper {
    // New execution delay to set for all roles: 11 days
    uint32 public constant NEW_DELAY = 11 days;

    function run() public override {
        super.run();

        // whitelist AA app
        _whitelistApp(0x14A1EC9b43c270a61cDD89B6CbdD985935D897fE);

        // Fetch deployed contracts
        AccessManager accessManager = AccessManager(_getChainDeployment("AccessManager"));
        KintoID kintoID = KintoID(_getChainDeployment("KintoID"));
        address nioGovernor = _getChainDeployment("NioGovernor");

        console2.log("Starting governance update script");
        console2.log("Current chain ID:", block.chainid);
        console2.log("AccessManager address:", address(accessManager));
        console2.log("KintoID address:", address(kintoID));
        console2.log("NioGovernor address:", nioGovernor);

        // Part 1: Update all necessary delays in AccessManager to 11 days
        address[] memory targetContracts = new address[](3);
        targetContracts[0] = address(kintoID);
        targetContracts[1] = _getChainDeployment("KintoAppRegistry");
        targetContracts[2] = _getChainDeployment("KintoWalletFactory");

        console2.log("Updating target admin delays to 11 days");
        for (uint256 i = 0; i < targetContracts.length; i++) {
            address target = targetContracts[i];
            uint32 currentDelay = accessManager.getTargetAdminDelay(target);
            console2.log("Contract", i, "current admin delay:", currentDelay);

            if (currentDelay < NEW_DELAY) {
                _handleOps(
                    abi.encodeWithSelector(AccessManager.setTargetAdminDelay.selector, target, NEW_DELAY),
                    address(accessManager)
                );
                vm.warp(block.timestamp + currentDelay + 1);
                uint32 updatedDelay = accessManager.getTargetAdminDelay(target);
                console2.log("Contract", i, "updated admin delay:", updatedDelay);
                require(updatedDelay == NEW_DELAY, "Admin delay update failed");
            } else {
                console2.log("Admin delay already >= 11 days, no update needed");
            }
        }

        // Part 2: Update execution delays for roles
        uint64[] memory roles = new uint64[](2);
        roles[0] = UPGRADER_ROLE;
        roles[1] = SECURITY_COUNCIL_ROLE;

        console2.log("Updating role execution delays");

        // Update L1_SECURITY_COUNCIL delays
        address L1_SECURITY_COUNCIL = 0x28fC10E12A78f986c78F973Fc70ED88072b34c8e;

        for (uint256 i = 0; i < roles.length; i++) {
            uint64 role = roles[i];
            (bool hasRole, uint32 currentDelay) = accessManager.hasRole(role, L1_SECURITY_COUNCIL);

            console2.log("Role", i, "current delay:", currentDelay);

            if (hasRole && currentDelay < NEW_DELAY) {
                _handleOps(
                    abi.encodeWithSelector(AccessManager.grantRole.selector, role, L1_SECURITY_COUNCIL, NEW_DELAY),
                    address(accessManager)
                );

                (, uint32 newDelay) = accessManager.hasRole(role, L1_SECURITY_COUNCIL);
                console2.log("Role", i, "updated delay:", newDelay);
                require(newDelay == NEW_DELAY, "Role delay update failed");
            } else if (hasRole) {
                console2.log("Role delay already >= 11 days, no update needed");
            } else {
                console2.log("L1 Security Council doesn't have this role");
            }
        }

        // Part 3: Revoke GOVERNANCE_ROLE from NioGovernor
        console2.log("Checking if NioGovernor has GOVERNANCE_ROLE");
        bool hasRole2 = kintoID.hasRole(kintoID.GOVERNANCE_ROLE(), nioGovernor);
        console2.log("NioGovernor has GOVERNANCE_ROLE:", hasRole2);

        if (hasRole2) {
            console2.log("Revoking GOVERNANCE_ROLE from NioGovernor");
            bytes memory data =
                abi.encodeWithSelector(IAccessControl.revokeRole.selector, kintoID.GOVERNANCE_ROLE(), nioGovernor);
            _handleOps(
                abi.encodeWithSelector(AccessManager.execute.selector, address(kintoID), data), address(accessManager)
            );

            bool roleRevoked = !kintoID.hasRole(kintoID.GOVERNANCE_ROLE(), nioGovernor);
            console2.log("GOVERNANCE_ROLE successfully revoked:", roleRevoked);
            require(roleRevoked, "Failed to revoke GOVERNANCE_ROLE from NioGovernor");
        } else {
            console2.log("NioGovernor doesn't have GOVERNANCE_ROLE, no action needed");
        }

        console2.log("Governance update script completed successfully");
    }
}

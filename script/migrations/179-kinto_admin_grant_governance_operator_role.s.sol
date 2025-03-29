// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";
import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";
import {KintoID} from "@kinto-core/KintoID.sol";
import {KintoWalletFactory} from "@kinto-core/wallet/KintoWalletFactory.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/console2.sol";

contract DeployScript is MigrationHelper {
    // Define a unique name for the GOVERNANCE_OPERATOR role
    uint64 constant GOVERNANCE_OPERATOR_ROLE = uint64(uint256(keccak256("GOVERNANCE_OPERATOR_ROLE")));

    // Address is calculated based on aliasing rules for L1 address
    address constant L1_SECURITY_COUNCIL = 0x28fC10E12A78f986c78F973Fc70ED88072b34c8e;

    // Store addresses to avoid stack too deep errors
    address internal accessManagerAddr;
    address internal kintoIDAddr;
    address internal walletFactoryAddr;

    uint32 constant ADMIN_DELAY = 12 days;

    function run() public override {
        super.run();

        console2.log("Starting GOVERNANCE_OPERATOR role creation script");
        console2.log("Current chain ID:", block.chainid);

        // Store addresses in storage variables to avoid stack too deep
        accessManagerAddr = _getChainDeployment("AccessManager");
        kintoIDAddr = _getChainDeployment("KintoID");
        walletFactoryAddr = _getChainDeployment("KintoWalletFactory");

        console2.log("AccessManager address:", accessManagerAddr);
        console2.log("KintoID address:", kintoIDAddr);
        console2.log("KintoWalletFactory address:", walletFactoryAddr);
        console2.log("kintoAdminWallet address:", kintoAdminWallet);
        console2.log("L1_SECURITY_COUNCIL address:", L1_SECURITY_COUNCIL);

        // Step 1: Define the function selectors
        bytes4[] memory kintoIDSelectors = new bytes4[](1);
        kintoIDSelectors[0] = KintoID.confirmSanction.selector;

        bytes4[] memory walletFactorySelectors = new bytes4[](1);
        walletFactorySelectors[0] = KintoWalletFactory.approveWalletRecovery.selector;

        console2.log("Setting up GOVERNANCE_OPERATOR role");

        // Step 2: Set up the function roles and label

        // Initialize AccessManager and check delays
        AccessManager accessManager = AccessManager(accessManagerAddr);

        // Prepare calldata for the operations
        bytes memory labelRoleData = abi.encodeWithSelector(
            AccessManager.labelRole.selector, GOVERNANCE_OPERATOR_ROLE, "GOVERNANCE_OPERATOR_ROLE"
        );

        bytes memory setKintoIDRoleData = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, kintoIDAddr, kintoIDSelectors, GOVERNANCE_OPERATOR_ROLE
        );

        bytes memory setWalletFactoryRoleData = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            walletFactoryAddr,
            walletFactorySelectors,
            GOVERNANCE_OPERATOR_ROLE
        );

        // Schedule the operations
        console2.log("Scheduling labelRole operation");
        _handleOps(
            abi.encodeWithSelector(AccessManager.schedule.selector, accessManagerAddr, labelRoleData, 0),
            accessManagerAddr
        );

        console2.log("Scheduling setTargetFunctionRole operation for KintoID");
        _handleOps(
            abi.encodeWithSelector(AccessManager.schedule.selector, accessManagerAddr, setKintoIDRoleData, 0),
            accessManagerAddr
        );

        console2.log("Scheduling setTargetFunctionRole operation for KintoWalletFactory");
        _handleOps(
            abi.encodeWithSelector(AccessManager.schedule.selector, accessManagerAddr, setWalletFactoryRoleData, 0),
            accessManagerAddr
        );

        // Warp time to after the admin delay
        console2.log("Current timestamp:", block.timestamp);
        console2.log("Warping time by:", ADMIN_DELAY + 1);
        vm.warp(block.timestamp + ADMIN_DELAY + 1);
        console2.log("New timestamp:", block.timestamp);

        // Execute the operations
        console2.log("Executing labelRole operation");
        _handleOps(
            abi.encodeWithSelector(AccessManager.execute.selector, accessManagerAddr, labelRoleData), accessManagerAddr
        );

        console2.log("Executing setTargetFunctionRole for KintoID");
        _handleOps(
            abi.encodeWithSelector(AccessManager.execute.selector, accessManagerAddr, setKintoIDRoleData),
            accessManagerAddr
        );

        console2.log("Executing setTargetFunctionRole for KintoWalletFactory");
        _handleOps(
            abi.encodeWithSelector(AccessManager.execute.selector, accessManagerAddr, setWalletFactoryRoleData),
            accessManagerAddr
        );

        // Step 3: Grant roles directly

        // Prepare call data for granting roles
        bytes memory kintoAdminGrantData = abi.encodeWithSelector(
            AccessManager.grantRole.selector, GOVERNANCE_OPERATOR_ROLE, kintoAdminWallet, uint32(NO_DELAY)
        );

        bytes memory securityCouncilGrantData = abi.encodeWithSelector(
            AccessManager.grantRole.selector, GOVERNANCE_OPERATOR_ROLE, L1_SECURITY_COUNCIL, uint32(NO_DELAY)
        );

        // Schedule operations due to target admin delay
        console2.log("Scheduling grantRole operation for kintoAdminWallet");
        _handleOps(
            abi.encodeWithSelector(AccessManager.schedule.selector, accessManagerAddr, kintoAdminGrantData, 0),
            accessManagerAddr
        );

        console2.log("Scheduling grantRole operation for L1_SECURITY_COUNCIL");
        _handleOps(
            abi.encodeWithSelector(AccessManager.schedule.selector, accessManagerAddr, securityCouncilGrantData, 0),
            accessManagerAddr
        );

        // Get scheduled time
        accessManager.getSchedule(accessManager.hashOperation(address(0), accessManagerAddr, kintoAdminGrantData));

        accessManager.getSchedule(accessManager.hashOperation(address(0), accessManagerAddr, securityCouncilGrantData));

        // Warp time to after the admin delay
        console2.log("Current timestamp:", block.timestamp);
        console2.log("Warping time by:", ADMIN_DELAY + 1);
        vm.warp(block.timestamp + ADMIN_DELAY + 1);
        console2.log("New timestamp:", block.timestamp);

        // Execute the operations
        console2.log("Executing grantRole for kintoAdminWallet");
        _handleOps(
            abi.encodeWithSelector(AccessManager.execute.selector, accessManagerAddr, kintoAdminGrantData),
            accessManagerAddr
        );

        console2.log("Executing grantRole for L1_SECURITY_COUNCIL");
        _handleOps(
            abi.encodeWithSelector(AccessManager.execute.selector, accessManagerAddr, securityCouncilGrantData),
            accessManagerAddr
        );

        // Step 4: Verify the grants were successful

        // Verify roles
        (bool isMember1, uint32 delay1) = accessManager.hasRole(GOVERNANCE_OPERATOR_ROLE, kintoAdminWallet);
        (bool isMember2, uint32 delay2) = accessManager.hasRole(GOVERNANCE_OPERATOR_ROLE, L1_SECURITY_COUNCIL);

        console2.log("kintoAdminWallet has role:", isMember1, "with delay:", delay1);
        console2.log("L1_SECURITY_COUNCIL has role:", isMember2, "with delay:", delay2);

        assertTrue(isMember1, "Role not granted to kintoAdminWallet");
        assertTrue(isMember2, "Role not granted to L1_SECURITY_COUNCIL");

        // Verify function access
        bytes4 confirmSanctionSelector = KintoID.confirmSanction.selector;
        bytes4 approveWalletRecoverySelector = KintoWalletFactory.approveWalletRecovery.selector;

        (bool immediate1,) = accessManager.canCall(kintoAdminWallet, kintoIDAddr, confirmSanctionSelector);
        (bool immediate2,) = accessManager.canCall(kintoAdminWallet, walletFactoryAddr, approveWalletRecoverySelector);
        (bool immediate3,) = accessManager.canCall(L1_SECURITY_COUNCIL, kintoIDAddr, confirmSanctionSelector);
        (bool immediate4,) =
            accessManager.canCall(L1_SECURITY_COUNCIL, walletFactoryAddr, approveWalletRecoverySelector);

        assertTrue(immediate1 && immediate2 && immediate3 && immediate4, "Function access verification failed");

        console2.log("GOVERNANCE_OPERATOR role creation script completed");
    }
}

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
    // Define unique roles
    uint64 constant RECOVERY_APPROVER_ROLE = uint64(uint256(keccak256("RECOVERY_APPROVER_ROLE")));
    uint64 constant SANCTIONER_ROLE = uint64(uint256(keccak256("SANCTIONER_ROLE")));

    // Address is calculated based on aliasing rules for L1 address
    address constant L1_SECURITY_COUNCIL = 0x28fC10E12A78f986c78F973Fc70ED88072b34c8e;

    // Store addresses to avoid stack too deep errors
    address internal accessManagerAddr;
    address internal kintoIDAddr;
    address internal walletFactoryAddr;

    uint32 constant ADMIN_DELAY = 12 days;

    function run() public override {
        super.run();

        console2.log("Starting role creation script");
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

        console2.log("Setting up RECOVERY_APPROVER_ROLE and SANCTIONER_ROLE");

        // Step 2: Set up the function roles and labels

        // Initialize AccessManager
        AccessManager accessManager = AccessManager(accessManagerAddr);

        // Function role assignments
        bytes memory setWalletFactoryRoleData = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector,
            walletFactoryAddr,
            walletFactorySelectors,
            RECOVERY_APPROVER_ROLE
        );

        bytes memory setKintoIDRoleData = abi.encodeWithSelector(
            AccessManager.setTargetFunctionRole.selector, kintoIDAddr, kintoIDSelectors, SANCTIONER_ROLE
        );

        // Schedule the operations
        console2.log("Scheduling labelRole operations");
        _handleOps(
            abi.encodeWithSelector(
                AccessManager.schedule.selector,
                accessManagerAddr,
                abi.encodeWithSelector(
                    AccessManager.labelRole.selector, RECOVERY_APPROVER_ROLE, "RECOVERY_APPROVER_ROLE"
                ),
                0
            ),
            accessManagerAddr
        );
        _handleOps(
            abi.encodeWithSelector(
                AccessManager.schedule.selector,
                accessManagerAddr,
                abi.encodeWithSelector(AccessManager.labelRole.selector, SANCTIONER_ROLE, "SANCTIONER_ROLE"),
                0
            ),
            accessManagerAddr
        );

        console2.log("Scheduling setTargetFunctionRole operations");
        _handleOps(
            abi.encodeWithSelector(AccessManager.schedule.selector, accessManagerAddr, setWalletFactoryRoleData, 0),
            accessManagerAddr
        );
        _handleOps(
            abi.encodeWithSelector(AccessManager.schedule.selector, accessManagerAddr, setKintoIDRoleData, 0),
            accessManagerAddr
        );

        // Warp time to after the admin delay
        console2.log("Current timestamp:", block.timestamp);
        console2.log("Warping time by:", ADMIN_DELAY + 1);
        vm.warp(block.timestamp + ADMIN_DELAY + 1);
        console2.log("New timestamp:", block.timestamp);

        // Execute the operations
        console2.log("Executing setTargetFunctionRole operations");
        _handleOps(
            abi.encodeWithSelector(AccessManager.execute.selector, accessManagerAddr, setWalletFactoryRoleData),
            accessManagerAddr
        );
        _handleOps(
            abi.encodeWithSelector(AccessManager.execute.selector, accessManagerAddr, setKintoIDRoleData),
            accessManagerAddr
        );

        // Step 3: Grant roles

        // Prepare call data for granting roles
        bytes memory kintoAdminRecoveryRoleData = abi.encodeWithSelector(
            AccessManager.grantRole.selector, RECOVERY_APPROVER_ROLE, kintoAdminWallet, uint32(NO_DELAY)
        );

        bytes memory securityCouncilSanctionerRoleData = abi.encodeWithSelector(
            AccessManager.grantRole.selector, SANCTIONER_ROLE, L1_SECURITY_COUNCIL, uint32(NO_DELAY)
        );

        // Schedule operations due to target admin delay
        console2.log("Scheduling grantRole operations");
        _handleOps(
            abi.encodeWithSelector(AccessManager.schedule.selector, accessManagerAddr, kintoAdminRecoveryRoleData, 0),
            accessManagerAddr
        );
        _handleOps(
            abi.encodeWithSelector(
                AccessManager.schedule.selector, accessManagerAddr, securityCouncilSanctionerRoleData, 0
            ),
            accessManagerAddr
        );

        // Get scheduled time
        accessManager.getSchedule(
            accessManager.hashOperation(address(0), accessManagerAddr, kintoAdminRecoveryRoleData)
        );
        accessManager.getSchedule(
            accessManager.hashOperation(address(0), accessManagerAddr, securityCouncilSanctionerRoleData)
        );

        // Warp time to after the admin delay
        console2.log("Current timestamp:", block.timestamp);
        console2.log("Warping time by:", ADMIN_DELAY + 1);
        vm.warp(block.timestamp + ADMIN_DELAY + 1);
        console2.log("New timestamp:", block.timestamp);

        // Execute the operations
        console2.log("Executing grantRole operations");
        _handleOps(
            abi.encodeWithSelector(AccessManager.execute.selector, accessManagerAddr, kintoAdminRecoveryRoleData),
            accessManagerAddr
        );
        _handleOps(
            abi.encodeWithSelector(AccessManager.execute.selector, accessManagerAddr, securityCouncilSanctionerRoleData),
            accessManagerAddr
        );

        // Step 4: Verify the grants were successful

        // Verify roles
        (bool isRecoveryApprover, uint32 recoveryDelay) =
            accessManager.hasRole(RECOVERY_APPROVER_ROLE, kintoAdminWallet);
        (bool isSanctioner, uint32 sanctionerDelay) = accessManager.hasRole(SANCTIONER_ROLE, L1_SECURITY_COUNCIL);

        console2.log("kintoAdminWallet has RECOVERY_APPROVER_ROLE:", isRecoveryApprover, "with delay:", recoveryDelay);
        console2.log("L1_SECURITY_COUNCIL has SANCTIONER_ROLE:", isSanctioner, "with delay:", sanctionerDelay);

        assertTrue(isRecoveryApprover, "RECOVERY_APPROVER_ROLE not granted to kintoAdminWallet");
        assertTrue(isSanctioner, "SANCTIONER_ROLE not granted to L1_SECURITY_COUNCIL");

        // Verify function access
        bytes4 confirmSanctionSelector = KintoID.confirmSanction.selector;
        bytes4 approveWalletRecoverySelector = KintoWalletFactory.approveWalletRecovery.selector;

        (bool recoveryAccess,) =
            accessManager.canCall(kintoAdminWallet, walletFactoryAddr, approveWalletRecoverySelector);
        (bool sanctionAccess,) = accessManager.canCall(L1_SECURITY_COUNCIL, kintoIDAddr, confirmSanctionSelector);

        assertTrue(recoveryAccess, "kintoAdminWallet cannot call approveWalletRecovery");
        assertTrue(sanctionAccess, "L1_SECURITY_COUNCIL cannot call confirmSanction");

        // Verify correct role separation
        (bool incorrectRecoveryAccess,) =
            accessManager.canCall(L1_SECURITY_COUNCIL, walletFactoryAddr, approveWalletRecoverySelector);
        (bool incorrectSanctionAccess,) = accessManager.canCall(kintoAdminWallet, kintoIDAddr, confirmSanctionSelector);

        assertTrue(!incorrectRecoveryAccess, "L1_SECURITY_COUNCIL incorrectly can call approveWalletRecovery");
        assertTrue(!incorrectSanctionAccess, "kintoAdminWallet incorrectly can call confirmSanction");

        console2.log("Role creation and assignment completed successfully");
    }
}

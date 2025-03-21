// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";
import {SponsorPaymaster} from "@kinto-core/paymasters/SponsorPaymaster.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";
import {KintoWalletFactory} from "@kinto-core/wallet/KintoWalletFactory.sol";
import {KintoWallet} from "@kinto-core/wallet/KintoWallet.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";
import {IKintoID} from "@kinto-core/interfaces/IKintoID.sol";
import {KintoID} from "@kinto-core/KintoID.sol";
import {IKintoAppRegistry} from "@kinto-core/interfaces/IKintoAppRegistry.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {IEntryPoint} from "@aa/interfaces/IEntryPoint.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import "forge-std/console2.sol";

/**
 * @title L1 Security Council Admin Script
 * @dev This script grants ADMIN_ROLE to the L1 Security Council with a delay
 */
contract DeployScript is MigrationHelper {
    // Address is calculated based on aliasing rules for L1 address, which is 0x17Eb10e12a78f986C78F973Fc70eD88072B33B7d
    // https://docs.kinto.xyz/kinto-the-modular-exchange/security-kyc-aml/security-council
    // https://docs.arbitrum.io/how-arbitrum-works/l1-to-l2-messaging#address-aliasing
    address constant L1_SECURITY_COUNCIL = 0x28fC10E12A78f986c78F973Fc70ED88072b34c8e;
    uint64 constant ADMIN_ROLE = 0; // AccessManager.ADMIN_ROLE is 0

    function run() public override {
        super.run();

        AccessManager accessManager = AccessManager(_getChainDeployment("AccessManager"));

        console2.log("Making L1 Security Council a global admin on AccessManager with delay");

        // Grant ADMIN_ROLE to L1_SECURITY_COUNCIL with SECURITY_COUNCIL_DELAY
        _handleOps(
            abi.encodeWithSelector(
                AccessManager.grantRole.selector, ADMIN_ROLE, L1_SECURITY_COUNCIL, uint32(SECURITY_COUNCIL_DELAY)
            ),
            address(accessManager)
        );

        // Need to wrap time since granting a role has a delay as well
        vm.warp(block.timestamp + SECURITY_COUNCIL_DELAY);

        // Verify that the role was granted correctly
        (bool isMember, uint32 currentDelay) = accessManager.hasRole(ADMIN_ROLE, L1_SECURITY_COUNCIL);
        assertTrue(isMember, "L1_SECURITY_COUNCIL should have ADMIN_ROLE");
        assertEq(currentDelay, SECURITY_COUNCIL_DELAY, "Delay should be set to SECURITY_COUNCIL_DELAY");

        console2.log(
            "L1 Security Council successfully made a global admin on AccessManager with delay of %s seconds",
            SECURITY_COUNCIL_DELAY
        );
    }
}

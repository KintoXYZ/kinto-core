// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";
import {SponsorPaymaster} from "@kinto-core/paymasters/SponsorPaymaster.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";
import {KintoWalletFactory} from "@kinto-core/wallet/KintoWalletFactory.sol";
import {KintoWallet} from "@kinto-core/wallet/KintoWallet.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
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

contract DeployScript is MigrationHelper {
    // Address is calculated based on aliasing rules for L1 address, which is 0x17Eb10e12a78f986C78F973Fc70eD88072B33B7d
    // https://docs.kinto.xyz/kinto-the-modular-exchange/security-kyc-aml/security-council
    // https://docs.arbitrum.io/how-arbitrum-works/l1-to-l2-messaging#address-aliasing
    address constant L1_SECURITY_COUNCIL = 0x28fC10E12A78f986c78F973Fc70ED88072b34c8e;

    function run() public override {
        super.run();

        AccessManager accessManager = AccessManager(_getChainDeployment("AccessManager"));
        address factory = _getChainDeployment("KintoWalletFactory");
        address registry = _getChainDeployment("KintoAppRegistry");
        KintoID kintoID = KintoID(_getChainDeployment("KintoID"));

        // give all the KintoID roles to the access manager
        _handleOps(
            abi.encodeWithSelector(
                IAccessControl.grantRole.selector, kintoID.DEFAULT_ADMIN_ROLE(), address(accessManager)
            ),
            address(kintoID)
        );
        _handleOps(
            abi.encodeWithSelector(
                IAccessControl.grantRole.selector, kintoID.KYC_PROVIDER_ROLE(), address(accessManager)
            ),
            address(kintoID)
        );
        _handleOps(
            abi.encodeWithSelector(IAccessControl.grantRole.selector, kintoID.UPGRADER_ROLE(), address(accessManager)),
            address(kintoID)
        );
        _handleOps(
            abi.encodeWithSelector(IAccessControl.grantRole.selector, kintoID.GOVERNANCE_ROLE(), address(accessManager)),
            address(kintoID)
        );

        assertTrue(kintoID.hasRole(kintoID.DEFAULT_ADMIN_ROLE(), address(accessManager)));
        assertTrue(kintoID.hasRole(kintoID.KYC_PROVIDER_ROLE(), address(accessManager)));
        assertTrue(kintoID.hasRole(kintoID.UPGRADER_ROLE(), address(accessManager)));
        assertTrue(kintoID.hasRole(kintoID.GOVERNANCE_ROLE(), address(accessManager)));

        bytes4[] memory kintoIDSelectors = new bytes4[](1);
        kintoIDSelectors[0] = UUPSUpgradeable.upgradeTo.selector;

        // set UPGRADER role for target functions for KintoID
        _handleOps(
            abi.encodeWithSelector(
                AccessManager.setTargetFunctionRole.selector, address(kintoID), kintoIDSelectors, UPGRADER_ROLE
            ),
            address(accessManager)
        );

        // grant role to a L1 security council with a delay
        _handleOps(
            abi.encodeWithSelector(
                AccessManager.grantRole.selector, UPGRADER_ROLE, L1_SECURITY_COUNCIL, uint32(UPGRADE_DELAY)
            ),
            address(accessManager)
        );

        // set delay on admin actions so admin can't move selectors to another role with no delay
        _handleOps(
            abi.encodeWithSelector(AccessManager.setTargetAdminDelay.selector, address(kintoID), UPGRADE_DELAY),
            address(accessManager)
        );

        // need to wrap time since granting a role has a delay as well
        vm.warp(block.timestamp + UPGRADE_DELAY);

        (bool immediate, uint32 delay) =
            accessManager.canCall(L1_SECURITY_COUNCIL, address(kintoID), UUPSUpgradeable.upgradeTo.selector);
        assertFalse(immediate);
        assertEq(delay, UPGRADE_DELAY);

        (bool isMember, uint32 currentDelay) = accessManager.hasRole(UPGRADER_ROLE, L1_SECURITY_COUNCIL);
        assertTrue(isMember);
        assertEq(currentDelay, UPGRADE_DELAY);

        // test that we can upgrade to a new KintoID
        KintoID newImpl = new KintoID(_getChainDeployment("KintoWalletFactory"), _getChainDeployment("Faucet"));

        bytes memory upgradeCalldata = abi.encodeWithSelector(UUPSUpgradeable.upgradeTo.selector, newImpl);

        vm.prank(L1_SECURITY_COUNCIL);
        accessManager.schedule(address(kintoID), upgradeCalldata, uint48(block.timestamp + UPGRADE_DELAY));

        vm.warp(block.timestamp + UPGRADE_DELAY);

        vm.prank(L1_SECURITY_COUNCIL);
        accessManager.execute(address(kintoID), upgradeCalldata);

        // Read implementation address from proxy storage and compare it to a new address
        assertEq(
            address(
                uint160(
                    uint256(
                        vm.load(
                            address(kintoID),
                            bytes32(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc)
                        )
                    )
                )
            ),
            address(newImpl)
        );

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = KintoAppRegistry.updateSystemApps.selector;
        selectors[1] = KintoAppRegistry.updateSystemContracts.selector;
        selectors[2] = KintoAppRegistry.updateReservedContracts.selector;

        // set functions for L1 council
        _handleOps(
            abi.encodeWithSelector(
                AccessManager.setTargetFunctionRole.selector, registry, selectors, SECURITY_COUNCIL_ROLE
            ),
            address(accessManager)
        );

        // grant role to the L1 council
        _handleOps(
            abi.encodeWithSelector(
                AccessManager.grantRole.selector,
                SECURITY_COUNCIL_ROLE,
                L1_SECURITY_COUNCIL,
                uint32(SECURITY_COUNCIL_DELAY)
            ),
            address(accessManager)
        );

        // Label the role
        _handleOps(
            abi.encodeWithSelector(AccessManager.labelRole.selector, SECURITY_COUNCIL_ROLE, "SECURITY_COUNCIL_ROLE"),
            address(accessManager)
        );

        (immediate, delay) =
            accessManager.canCall(L1_SECURITY_COUNCIL, registry, KintoAppRegistry.updateSystemApps.selector);
        assertFalse(immediate);
        assertEq(delay, SECURITY_COUNCIL_DELAY);

        (isMember, currentDelay) = accessManager.hasRole(SECURITY_COUNCIL_ROLE, L1_SECURITY_COUNCIL);
        assertTrue(isMember);
        assertEq(currentDelay, SECURITY_COUNCIL_DELAY);
    }
}

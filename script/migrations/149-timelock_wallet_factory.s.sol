// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {SponsorPaymaster} from "@kinto-core/paymasters/SponsorPaymaster.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";
import {KintoWalletFactory} from "@kinto-core/wallet/KintoWalletFactory.sol";
import {KintoWallet} from "@kinto-core/wallet/KintoWallet.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";
import {IKintoID} from "@kinto-core/interfaces/IKintoID.sol";
import {IKintoAppRegistry} from "@kinto-core/interfaces/IKintoAppRegistry.sol";
import {IEntryPoint} from "@aa/interfaces/IEntryPoint.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        AccessManager accessManager = AccessManager(_getChainDeployment("AccessManager"));
        address factory = _getChainDeployment("KintoWalletFactory");
        address registry = _getChainDeployment("KintoAppRegistry");

        _whitelistApp(address(accessManager));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = KintoWalletFactory.upgradeAllWalletImplementations.selector;

        // set UPGRADER role for target functions for KintoWalletFactory
        _handleOps(
            abi.encodeWithSelector(AccessManager.setTargetFunctionRole.selector, factory, selectors, UPGRADER_ROLE),
            address(accessManager)
        );

        selectors[0] = UUPSUpgradeable.upgradeTo.selector;
        // set UPGRADER role for target functions AppRegistry
        _handleOps(
            abi.encodeWithSelector(AccessManager.setTargetFunctionRole.selector, registry, selectors, UPGRADER_ROLE),
            address(accessManager)
        );

        // grant role to a Safe with a delay
        _handleOps(
            abi.encodeWithSelector(
                AccessManager.grantRole.selector, UPGRADER_ROLE, kintoAdminWallet, uint32(UPGRADE_DELAY)
            ),
            address(accessManager)
        );

        // label the role
        _handleOps(
            abi.encodeWithSelector(AccessManager.labelRole.selector, UPGRADER_ROLE, "UPGRADER_ROLE"),
            address(accessManager)
        );

        // set grantDelay, so admin can't grant the same role to another account with no delay
        _handleOps(
            abi.encodeWithSelector(AccessManager.setGrantDelay.selector, UPGRADER_ROLE, UPGRADE_DELAY),
            address(accessManager)
        );

        // set delay on admin actions so admin can't move selectors to another role with no delay
        _handleOps(
            abi.encodeWithSelector(AccessManager.setTargetAdminDelay.selector, address(factory), UPGRADE_DELAY),
            address(accessManager)
        );

        // transfer wallet factory ownership to access manager
        _handleOps(abi.encodeWithSelector(Ownable.transferOwnership.selector, accessManager), address(factory));

        // transfer app registry ownership to access manager
        _handleOps(abi.encodeWithSelector(Ownable.transferOwnership.selector, accessManager), address(registry));

        assertEq(KintoWalletFactory(factory).owner(), address(accessManager));

        (bool immediate, uint32 delay) = accessManager.canCall(
            kintoAdminWallet, factory, KintoWalletFactory.upgradeAllWalletImplementations.selector
        );
        assertFalse(immediate);
        assertEq(delay, UPGRADE_DELAY);

        (bool isMember, uint32 currentDelay) = accessManager.hasRole(UPGRADER_ROLE, kintoAdminWallet);
        assertTrue(isMember);
        assertEq(currentDelay, UPGRADE_DELAY);

        // test that we can upgrade to a new wallet
        KintoWallet newImpl = new KintoWallet(
            IEntryPoint(ENTRY_POINT),
            IKintoID(_getChainDeployment("KintoID")),
            IKintoAppRegistry(_getChainDeployment("KintoAppRegistry")),
            KintoWalletFactory(factory)
        );

        bytes memory upgradeAllCalldata =
            abi.encodeWithSelector(KintoWalletFactory.upgradeAllWalletImplementations.selector, newImpl);

        vm.prank(kintoAdminWallet);
        accessManager.schedule(factory, upgradeAllCalldata, uint48(block.timestamp + UPGRADE_DELAY));

        vm.warp(block.timestamp + UPGRADE_DELAY);

        vm.prank(kintoAdminWallet);
        accessManager.execute(factory, upgradeAllCalldata);

        assertEq(address(newImpl), KintoWalletFactory(factory).beacon().implementation());

        // test that we can upgrade to a app registry
        KintoAppRegistry newAppRegistry =
            new KintoAppRegistry(KintoWalletFactory(factory), SponsorPaymaster(_getChainDeployment("SponsorPaymaster")));
        bytes memory upgradeCalldata = abi.encodeWithSelector(UUPSUpgradeable.upgradeTo.selector, newAppRegistry);

        vm.prank(kintoAdminWallet);
        accessManager.schedule(registry, upgradeCalldata, uint48(block.timestamp + UPGRADE_DELAY));

        vm.warp(block.timestamp + UPGRADE_DELAY);

        vm.prank(kintoAdminWallet);
        accessManager.execute(registry, upgradeCalldata);

        // Read implementation address from proxy storage and compare it to a new address
        assertEq(
            address(
                uint160(
                    uint256(
                        vm.load(registry, bytes32(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc))
                    )
                )
            ),
            address(newAppRegistry)
        );
    }
}

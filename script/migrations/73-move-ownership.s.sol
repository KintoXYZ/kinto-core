// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {UUPSUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";
import {KintoID} from "@kinto-core/KintoID.sol";
import {KintoWalletFactory} from "@kinto-core/wallet/KintoWalletFactory.sol";
import {SponsorPaymaster} from "@kinto-core/paymasters/SponsorPaymaster.sol";

import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract MoveOwnershipScript is MigrationHelper {
    function run() public override {
        super.run();

        address adminWallet = _getChainDeployment("KintoWallet-admin");
        address ledger = 0xc1f4D15C16A1f3555E0a5F7AeFD1e17AD4aaf40B;

        KintoAppRegistry kintoAppRegistry = KintoAppRegistry(payable(_getChainDeployment("KintoAppRegistry")));
        KintoID kintoID = KintoID(payable(_getChainDeployment("KintoID")));
        KintoWalletFactory kintoWalletFactory = KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));
        SponsorPaymaster sponsorPaymaster = SponsorPaymaster(payable(_getChainDeployment("SponsorPaymaster")));

        vm.startBroadcast(); // requires LEDGER_ADMIN
        //vm.startPrank(ledger);

        // KintoAppRegistry
        kintoAppRegistry.transferOwnership(adminWallet);
        assertEq(kintoAppRegistry.owner(), adminWallet);

        // KintoID
        kintoID.grantRole(kintoID.KYC_PROVIDER_ROLE(), adminWallet);
        kintoID.grantRole(kintoID.UPGRADER_ROLE(), adminWallet);
        kintoID.grantRole(kintoID.DEFAULT_ADMIN_ROLE(), adminWallet);

        kintoID.revokeRole(kintoID.KYC_PROVIDER_ROLE(), ledger);
        kintoID.revokeRole(kintoID.UPGRADER_ROLE(), ledger);
        kintoID.revokeRole(kintoID.DEFAULT_ADMIN_ROLE(), ledger);

        assertFalse(kintoID.hasRole(kintoID.DEFAULT_ADMIN_ROLE(), ledger));
        assertFalse(kintoID.hasRole(kintoID.KYC_PROVIDER_ROLE(), ledger));
        assertFalse(kintoID.hasRole(kintoID.UPGRADER_ROLE(), ledger));

        assertTrue(kintoID.hasRole(kintoID.DEFAULT_ADMIN_ROLE(), adminWallet));
        assertTrue(kintoID.hasRole(kintoID.KYC_PROVIDER_ROLE(), adminWallet));
        assertTrue(kintoID.hasRole(kintoID.UPGRADER_ROLE(), adminWallet));

        // KintoWalletFactory
        kintoWalletFactory.transferOwnership(adminWallet);
        assertEq(kintoWalletFactory.owner(), adminWallet);

        //SponsorPaymaster
        sponsorPaymaster.transferOwnership(adminWallet);
        assertEq(sponsorPaymaster.owner(), adminWallet);

        //vm.stopPrank();
        vm.stopBroadcast();
    }
}

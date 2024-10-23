// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/wallet/KintoWallet.sol";
import "@kinto-core/wallet/KintoWalletFactory.sol";
import "@kinto-core/apps/KintoAppRegistry.sol";

import "../../../test/helpers/ArtifactsReader.sol";

import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

/// @notice This script upgrades the KintoWalletFactory implementation
contract KintoWalletFactoryUpgradeScript is ArtifactsReader {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy new version of KintoWalletFactory
        KintoWalletFactory _newImplementation = new KintoWalletFactory(
            KintoWallet(payable(_getChainDeployment("KintoWallet-impl"))),
            KintoAppRegistry(_getChainDeployment("KintoAppRegistry")),
            IKintoID(_getChainDeployment("KintoID")),
            RewardsDistributor(_getChainDeployment("RewardsDistributor"))
        );

        // upgrade KintoWalletFactory to new version
        KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory"))).upgradeTo(address(_newImplementation));
        console.log("KintoWalletFactory Upgraded to implementation", address(_newImplementation));

        vm.stopBroadcast();
    }
}

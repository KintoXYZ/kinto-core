// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../../src/wallet/KintoWallet.sol";
import "../../../src/wallet/KintoWalletFactory.sol";
import "../../../src/apps/KintoAppRegistry.sol";

import "../../../test/helpers/ArtifactsReader.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoWalletFactoryNewVersion is KintoWalletFactory {
    constructor(KintoWallet _impl, KintoAppRegistry _app, IKintoID _kintoID)
        KintoWalletFactory(_impl, _app, _kintoID)
    {}
}

/// @notice This script upgrades the KintoWalletFactory implementation
contract KintoWalletFactoryUpgradeScript is ArtifactsReader {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy new version of KintoWalletFactory
        KintoWalletFactoryNewVersion _newImplementation = new KintoWalletFactoryNewVersion(
            KintoWallet(payable(_getChainDeployment("KintoWallet-impl"))),
            KintoAppRegistry(_getChainDeployment("KintoAppRegistry")),
            IKintoID(_getChainDeployment("KintoID"))
        );

        // upgrade KintoWalletFactory to new version
        KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory"))).upgradeTo(address(_newImplementation));
        console.log("KintoWalletFactory Upgraded to implementation", address(_newImplementation));

        vm.stopBroadcast();
    }
}

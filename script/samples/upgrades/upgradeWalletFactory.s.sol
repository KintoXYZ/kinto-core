// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../../src/wallet/KintoWallet.sol";
import "../../../src/wallet/KintoWalletFactory.sol";

import "../../../test/helpers/ArtifactsReader.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface Upgradeable {
    function upgradeTo(address newImplementation) external;
}

contract KintoWalletFactoryNewVersion is KintoWalletFactory {
    constructor(KintoWallet _impl) KintoWalletFactory(_impl) {}
}

/// @notice This script upgrades the KintoWalletFactory implementation
contract KintoWalletFactoryUpgradeScript is ArtifactsReader {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy new version of KintoWalletFactory
        KintoWalletFactoryNewVersion _newImplementation =
            new KintoWalletFactoryNewVersion(KintoWallet(payable(_getChainDeployment("KintoWallet-impl"))));

        // upgrade KintoWalletFactory to new version
        KintoWalletFactory kintoWalletFactory = KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));
        try kintoWalletFactory.UPGRADE_INTERFACE_VERSION() {
            Upgradeable(_getChainDeployment("KintoWalletFactory")).upgradeTo(address(_newImplementation));
        } catch {
            KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory"))).upgradeToAndCall(address(_newImplementation), bytes(""));
        }
        console.log("KintoWalletFactory Upgraded to implementation", address(_newImplementation));

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../../src/KintoID.sol";
import "../../../src/wallet/KintoWallet.sol";
import "../../../src/interfaces/IKintoID.sol";
import "../../../src/wallet/KintoWalletFactory.sol";

import "../../../test/helpers/ArtifactsReader.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoWalletNewVersion is KintoWallet {
    constructor(IEntryPoint _entryPoint, IKintoID _kintoID, IKintoAppRegistry _kintoApp, IKintoWalletFactory _factory)
        KintoWallet(_entryPoint, _kintoID, _kintoApp, _factory)
    {}
}

/// @notice This script upgrades the KintoWallet implementation by calling the `upgradeAllWalletImplementations` function of the KintoWalletFactory
contract KintoWalletsUpgradeScript is ArtifactsReader {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy new wallet implementation
        KintoWallet _kintoWalletImpl = new KintoWalletNewVersion(
            IEntryPoint(_getChainDeployment("EntryPoint")),
            IKintoID(_getChainDeployment("KintoID")),
            IKintoAppRegistry(_getChainDeployment("IKintoAppRegistry")),
            IKintoWalletFactory(_getChainDeployment("KintoWalletFactory"))
        );

        // upgrade all implementations
        KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory"))).upgradeAllWalletImplementations(
            _kintoWalletImpl
        );
        vm.stopBroadcast();
    }
}

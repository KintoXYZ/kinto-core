// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../../src/KintoID.sol";
import "../../../src/interfaces/IKintoID.sol";
import "../../../test/helpers/ArtifactsReader.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoIDV2 is KintoID {
    constructor(address _walletFactory, address _faucet) KintoID(_walletFactory, _faucet) {}
}

contract KintoIDUpgradeScript is ArtifactsReader {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy new version of KintoID
        KintoIDV2 implementation = new KintoIDV2(_getChainDeployment("KintoID"), _getChainDeployment("Faucet"));

        // upgrade KintoID to new version
        KintoID(payable(_getChainDeployment("KintoID"))).upgradeTo(address(implementation));
        console.log("KintoID upgraded to implementation", address(implementation));

        vm.stopBroadcast();
    }
}

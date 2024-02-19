// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../../src/KintoID.sol";
import "../../../src/interfaces/IKintoID.sol";
import "../../../test/helpers/ArtifactsReader.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface Upgradeable {
    function upgradeTo(address newImplementation) external;
}

contract KintoIDV2 is KintoID {
    constructor(address _walletFactory) KintoID(_walletFactory) {}
}

contract KintoIDUpgradeScript is ArtifactsReader {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // deploy new version of KintoID
        KintoIDV2 implementation = new KintoIDV2(_getChainDeployment("KintoID"));

        // upgrade KintoID to new version
        KintoID kintoID = KintoID(payable(_getChainDeployment("KintoID")));
        try kintoID.UPGRADE_INTERFACE_VERSION() {
            Upgradeable(_getChainDeployment("KintoID")).upgradeTo(address(implementation));
        } catch {
            KintoID(payable(_getChainDeployment("KintoID"))).upgradeToAndCall(address(implementation), bytes(""));
        }
        console.log("KintoID upgraded to implementation", address(implementation));

        vm.stopBroadcast();
    }
}

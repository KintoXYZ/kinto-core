// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/KintoID.sol";
import {Create2Helper} from "../../test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "../../test/helpers/UUPSProxy.sol";
import {KYCSignature} from "../../test/helpers/KYCSignature.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/console.sol";

contract KintoMigration3DeployScript is Create2Helper, KYCSignature, ArtifactsReader {
    using ECDSAUpgradeable for bytes32;

    KintoID _kintoIDv1;

    function setUp() public {}

    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // If not using ledger, replace
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.rememberKey(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);
        console.log("Executing with address", deployer);
        // vm.startBroadcast();
        address walletFactoryAddr = _getChainDeployment("KintoWalletFactory");
        if (walletFactoryAddr == address(0)) {
            console.log("Need to execute main deploy script first", walletFactoryAddr);
            return;
        }
        // Mint an nft to the owner
        _kintoIDv1 = KintoID(_getChainDeployment("KintoID"));
        IKintoID.SignatureData memory sigdata =
            _auxCreateSignature(_kintoIDv1, deployer, deployer, deployerPrivateKey, block.timestamp + 1000);
        vm.stopBroadcast();
        vm.startBroadcast();
        uint8[] memory traits = new uint8[](1);
        traits[0] = 0; // ADMIN
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        vm.stopBroadcast();
    }
}

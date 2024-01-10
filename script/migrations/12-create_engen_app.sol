// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/KintoID.sol";
import "../../src/wallet/KintoWallet.sol";
import {Create2Helper} from "../../test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "../../test/helpers/UUPSProxy.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/console.sol";

contract KintoMigration12DeployScript is Create2Helper, ArtifactsReader {
    using ECDSAUpgradeable for bytes32;

    KintoWalletFactory _walletFactory;
    KintoWallet _kintoWalletv1;
    KintoID _kintoIDv1;
    UUPSProxy _proxy;

    function setUp() public {}

    // solhint-disable code-complexity
    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // Execute using hot wallet
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.rememberKey(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);
        console.log("Executing with address", deployer);
        address walletFactoryAddr = _getChainDeployment("KintoWalletFactory");
        if (walletFactoryAddr == address(0)) {
            console.log("Need to execute main deploy script first", walletFactoryAddr);
            return;
        }
        address credits = _getChainDeployment("EngenCredits");
        IKintoAppRegistry _kintoApp = IKintoAppRegistry(_getChainDeployment("KintoAppRegistry"));

        // TODO: This needs to go through the entry point and the wallet we created in 4
        // _kintoApp.initialize();
        // Create Engen App
        // _kintoApp.registerApp("Engen", credits, new address[](0), [uint256(0), uint256(0), uint256(0), uint256(0)]);

        vm.stopBroadcast();

        // Writes the addresses to a file
        console.log("Engen APP created and minted");
    }
}

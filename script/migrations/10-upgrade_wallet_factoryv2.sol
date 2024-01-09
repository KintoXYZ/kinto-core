// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../../src/wallet/KintoWalletFactory.sol";
import {KintoWallet} from "../../src/wallet/KintoWallet.sol";
import {Create2Helper} from "../../test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "../../test/helpers/UUPSProxy.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/console.sol";

contract KintoMigration9DeployScript is Create2Helper, ArtifactsReader {
    using ECDSAUpgradeable for bytes32;

    KintoWalletFactory _walletFactory;
    KintoWalletFactoryV2 _factoryImpl;
    UUPSProxy _proxy;

    function setUp() public {}

    // solhint-disable code-complexity
    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // Execute this script with the ledger admin
        console.log("Executing with address", msg.sender);
        vm.startBroadcast();
        address factoryAddr = _getChainDeployment("KintoWalletFactory");
        if (factoryAddr == address(0)) {
            console.log("Need to execute main deploy script first", factoryAddr);
            return;
        }
        _walletFactory = KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));

        address newImpl = _getChainDeployment("KintoWalletV3-impl");
        if (newImpl == address(0)) {
            console.log("Need to deploy the new wallet first", newImpl);
            return;
        }
        bytes memory bytecode = abi.encodePacked(
            abi.encodePacked(type(KintoWalletFactoryV2).creationCode),
            abi.encode(_getChainDeployment("KintoWalletV3-impl")) // Encoded constructor arguments
        );

        // Deploy new paymaster implementation
        _factoryImpl = KintoWalletFactoryV2(payable(_walletFactory.deployContract(msg.sender, 0, bytecode, bytes32(0))));
        // Upgrade
        _walletFactory.upgradeTo(address(_factoryImpl));
        vm.stopBroadcast();
        // Writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"KintoWalletFactoryV2-impl": "', vm.toString(address(_factoryImpl)), '"'));
    }
}

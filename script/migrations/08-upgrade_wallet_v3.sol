// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/wallet/KintoWallet.sol";
import {Create2Helper} from "../../test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "../../test/helpers/UUPSProxy.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/console.sol";

contract KintoMigration8DeployScript is Create2Helper, ArtifactsReader {
    using ECDSAUpgradeable for bytes32;

    KintoWalletFactory _walletFactory;
    KintoWalletV3 _kintoWalletImpl;
    UUPSProxy _proxy;

    function setUp() public {}

    // solhint-disable code-complexity
    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // Execute this script with the ledger admin
        console.log("Executing with address", msg.sender);
        vm.startBroadcast();
        address walletFactoryAddr = _getChainDeployment("KintoWalletFactory");
        if (walletFactoryAddr == address(0)) {
            console.log("Need to execute main deploy script first", walletFactoryAddr);
            return;
        }
        address kintoAppAddr = _getChainDeployment("KintoAppRegistry");
        if (kintoAppAddr == address(0)) {
            console.log("Need to deploy kinto app registry first", kintoAppAddr);
            return;
        }
        _walletFactory = KintoWalletFactory(payable(walletFactoryAddr));

        bytes memory bytecode = abi.encodePacked(
            abi.encodePacked(type(KintoWalletV3).creationCode),
            abi.encode(
                _getChainDeployment("EntryPoint"),
                IKintoID(_getChainDeployment("KintoID")),
                IKintoAppRegistry(_getChainDeployment("KintoAppRegistry"))
            ) // Encoded constructor arguments
        );

        // Deploy new wallet implementation
        _kintoWalletImpl = KintoWalletV3(payable(_walletFactory.deployContract(msg.sender, 0, bytecode, bytes32(0))));
        // Upgrade all implementations
        _walletFactory.upgradeAllWalletImplementations(_kintoWalletImpl);
        vm.stopBroadcast();
        // Writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"KintoWalletV3-impl": "', vm.toString(address(_kintoWalletImpl)), '"'));
    }
}

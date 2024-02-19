// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import {KintoWallet} from "../../src/wallet/KintoWallet.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Upgradeable version of KintoWallet
contract KintoWalletV2 is KintoWallet {
    constructor(IEntryPoint _entryPoint, IKintoID _kintoID)
        KintoWallet(_entryPoint, _kintoID, IKintoAppRegistry(address(0)))
    {}
}

contract KintoMigration2DeployScript is Create2Helper, ArtifactsReader {
    using MessageHashUtils for bytes32;

    KintoWalletFactory _walletFactory;
    KintoWalletV2 _kintoWalletImpl;
    UUPSProxy _proxy;

    function setUp() public {}

    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // If not using ledger, replace
        // uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        // vm.startBroadcast(deployerPrivateKey);
        console.log("Executing with address", msg.sender);
        vm.startBroadcast();
        address walletFactoryAddr = _getChainDeployment("KintoWalletFactory");
        if (walletFactoryAddr == address(0)) {
            console.log("Need to execute main deploy script first", walletFactoryAddr);
            return;
        }
        _walletFactory = KintoWalletFactory(payable(walletFactoryAddr));
        // Deploy new wallet implementation
        _kintoWalletImpl =
            new KintoWalletV2(IEntryPoint(_getChainDeployment("EntryPoint")), IKintoID(_getChainDeployment("KintoID")));
        // // Upgrade all implementations
        _walletFactory.upgradeAllWalletImplementations(_kintoWalletImpl);
        vm.stopBroadcast();

        // Writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"KintoWalletV2-impl": "', vm.toString(address(_kintoWalletImpl)), '"'));
    }
}

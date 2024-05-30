// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/KintoID.sol";
import "../../src/wallet/KintoWallet.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoMigration4DeployScript is Create2Helper, ArtifactsReader {
    KintoWalletFactory _walletFactory;
    KintoWallet _kintoWalletv1;
    KintoID _kintoID;
    UUPSProxy _proxy;

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
        _walletFactory = KintoWalletFactory(walletFactoryAddr);
        // deploy walletv1 through wallet factory and initializes it
        _kintoWalletv1 = KintoWallet(payable(address(_walletFactory.createAccount(deployer, msg.sender, 0))));
        vm.stopBroadcast();

        // Writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"KintoWallet-admin": "', vm.toString(address(_kintoWalletv1)), '"'));
    }
}

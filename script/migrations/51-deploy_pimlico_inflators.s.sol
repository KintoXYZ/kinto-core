// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {KintoID} from "../../src/KintoID.sol";
import {KintoWalletFactory} from "../../src/wallet/KintoWalletFactory.sol";
import {Faucet} from "../../src/Faucet.sol";
import {KintoInflator} from "../../src/inflators/KintoInflator.sol";
import {BundleBulker} from "../../src/inflators/BundleBulker.sol";
import {IInflator} from "../../src/interfaces/IInflator.sol";
import {PerOpInflator, IOpInflator} from "@alto/src/Compression/PerOpInflator.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/console2.sol";

contract KintoMigration51DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        address kintoWalletAdmin = _getChainDeployment("KintoWallet-admin");
        address perOpInflatorOwner = kintoWalletAdmin;

        if (_getChainDeployment("BundleBulker") == address(0)) revert("BundleBulker is not deployed");

        // deploy PerOpInflator through KintoWalletFactory convenient contract and assign ownership to KintoWallet-admin
        bytes memory bytecode = abi.encodePacked(type(PerOpInflator).creationCode, abi.encode(perOpInflatorOwner));
        vm.broadcast(deployerPrivateKey);
        address perOpInflator = factory.deployContract(kintoWalletAdmin, 0, bytecode, bytes32(0));
        console2.log("PerOpInflator deployed @", perOpInflator);

        // register PerOpInflator in BundleBulker (can be called directly since BundleBulker is whitelisted at Geth level)
        vm.broadcast(deployerPrivateKey);
        BundleBulker(_getChainDeployment("BundleBulker")).registerInflator(1, IInflator(perOpInflator));
        console2.log("PerOpInflator registered on BundleBulker");

        _whitelistApp(perOpInflator, true);
        console2.log("PerOpInflator whitelisted on KintoWallet-admin");

        // register Kinto's Inflator in PerOpInflator via handleOps
        _handleOps(
            abi.encodeWithSelector(
                PerOpInflator.registerOpInflator.selector, 1, IOpInflator(_getChainDeployment("KintoInflator"))
            ),
            kintoWalletAdmin,
            perOpInflator,
            deployerPrivateKey
        );

        // transfer PerOpInflator ownership to Pimlico
        // address pimlicoKintoWallet = ;
        // make sure that Pimlico's KintoWallet is a KintoWallet
        // require(factory.walletTs(pimlicoKintoWallet) > 0, "Pimlico's wallet is not a KintoWallet");
        // transfer PerOpInflator ownership to KintoWallet-admin
        // _transferOwnership(perOpInflator, deployerPrivateKey, pimlicoKintoWallet);
    }
}

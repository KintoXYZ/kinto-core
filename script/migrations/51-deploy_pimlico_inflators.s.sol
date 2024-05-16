// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {KintoID} from "../../src/KintoID.sol";
import {KintoWalletFactory} from "../../src/wallet/KintoWalletFactory.sol";
import {Faucet} from "../../src/Faucet.sol";
import {KintoInflator} from "../../src/inflators/KintoInflator.sol";
import {BundleBulker} from "../../src/inflators/BundleBulker.sol";
import {IInflator} from "../../src/interfaces/IInflator.sol";
import {PerOpInflator, IOpInflator} from "@alto/src/compression/PerOpInflator.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration51DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        // assert that sender is KYC'd
        address pimlicoSignerAddress = 0x433704c40F80cBff02e86FD36Bc8baC5e31eB0c1;
        if (msg.sender != pimlicoSignerAddress) revert("Sender must be 0x433704c40F80cBff02e86FD36Bc8baC5e31eB0c1 ");
        if (!KintoID(_getChainDeployment("KintoID")).isKYC(pimlicoSignerAddress)) {
            revert("0x433704c40F80cBff02e86FD36Bc8baC5e31eB0c1 must be KYC'd");
        }
        if (_getChainDeployment("BundleBulker") == address(0)) revert("BundleBulker is not deployed");

        // create Pimlico's smart account on Kinto
        address pimlicoPubKey = vm.addr(deployerPrivateKey);
        vm.broadcast(deployerPrivateKey);
        address pimlicoKintoWallet = address(
            KintoWalletFactory(_getChainDeployment("KintoWalletFactory")).createAccount(pimlicoPubKey, pimlicoPubKey, 0)
        );
        console.log("Pimlico's wallet created @", pimlicoKintoWallet);

        deal(pimlicoPubKey, 0 ether);
        vm.broadcast(deployerPrivateKey);
        Faucet(payable(_getChainDeployment("Faucet"))).claimKintoETH();
        console.log("Claimed Kinto ETH from Faucet. Account balance is:", pimlicoPubKey.balance);

        // deploy PerOpInflator using Pimlico's signer (which is KYC'd) through KintoWalletFactory convenient contract
        bytes memory bytecode = abi.encodePacked(type(PerOpInflator).creationCode, abi.encode(pimlicoKintoWallet));
        vm.broadcast(deployerPrivateKey);
        address perOpInflator = factory.deployContract(pimlicoKintoWallet, 0, bytecode, bytes32(0));
        console.log("PerOpInflator deployed @", perOpInflator);

        // register PerOpInflator in BundleBulker (can be called directly since BundleBulker is whitelisted at Geth level)
        vm.broadcast(deployerPrivateKey);
        BundleBulker(_getChainDeployment("BundleBulker")).registerInflator(1, IInflator(perOpInflator));
        console.log("PerOpInflator registered on BundleBulker");

        // fund Pimlico Wallet so it can pay for gas
        _fundPaymaster(pimlicoKintoWallet, deployerPrivateKey);
        console.log("Pimlico's wallet funded on Paymaster");

        // whitelist PerOpInflator on Pimlico's wallet so it can call it
        _whitelistApp(perOpInflator, pimlicoKintoWallet, deployerPrivateKey, true);
        console.log("PerOpInflator whitelisted on Pimlico's wallet");

        // fund PerOpInflator so it can pay for gas
        _fundPaymaster(perOpInflator, deployerPrivateKey);
        console.log("PerOpInflator funded on Paymaster");

        // register Kinto's Inflator in PerOpInflator via handleOps
        _handleOps(
            abi.encodeWithSelector(
                PerOpInflator.registerOpInflator.selector, 1, IOpInflator(_getChainDeployment("KintoInflator"))
            ),
            pimlicoKintoWallet, // from
            perOpInflator, // to
            deployerPrivateKey // signer
        );
    }
}

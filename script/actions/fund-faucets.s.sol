// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {KintoWalletFactory} from "@kinto-core/wallet/KintoWalletFactory.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ArrayHelpers} from "@kinto-core-test/helpers/ArrayHelpers.sol";
import "forge-std/console2.sol";

contract FundFaucetsScript is MigrationHelper {
    using ArrayHelpers for *;

    address public constant FAUCET = 0x0719D47A213149E2Ef8d3f5afDaDA8a8E22dfc03;
    address public constant WALLET_FUNDER = 0x4062E762EC9E2E70f40bd9586C18d1894966628F;
    address public constant FAUCET_CLAIMER = 0x52F09693c9eEaA93A64BA697e3d3e43a1eB65477;
    address public constant KYC_RELAYER = 0x6E31039abF8d248aBed57E307C9E1b7530c269E4;

    function run() public override {
        super.run();

        console2.log('Hot Wallet Balance: %e', deployer.balance);
        if(deployer.balance < 0.25 ether) {
            console2.log('Hot Wallet Balance too low. Refill.');
            return;
        }

        address[4] memory faucets = [FAUCET, WALLET_FUNDER, FAUCET_CLAIMER, KYC_RELAYER];
        string[4] memory names = ["FAUCET", "WALLET_FUNDER", "FAUCET_CLAIMER", "KYC_RELAYER"];
        uint64[4] memory limits = [0.25 ether, 0.25 ether, 0.25 ether, 0.25 ether];
        uint64[4] memory amounts = [0.25 ether, 0.25 ether, 0.25 ether, 0.25 ether];

        for (uint256 index = 0; index < faucets.length; index++) {
            address faucet = faucets[index];
            uint256 balance = faucet.balance;
            console2.log('Faucet:', names[index]);
            console2.log('Address:', faucets[index]);
            console2.log('Balance: %e', balance);

            if (balance < limits[index]) {
                console2.log('Needs funding. Adding:', amounts[index]);

                KintoWalletFactory factory = KintoWalletFactory(_getChainDeployment("KintoWalletFactory"));
                vm.broadcast(deployerPrivateKey);
                factory.sendMoneyToAccount{value: amounts[index]}(faucet);
            }
        }
    }
}

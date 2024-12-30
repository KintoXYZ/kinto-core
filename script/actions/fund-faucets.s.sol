// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {KintoWalletFactory} from "@kinto-core/wallet/KintoWalletFactory.sol";
import {SponsorPaymaster} from "@kinto-core/paymasters/SponsorPaymaster.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {ArrayHelpers} from "@kinto-core-test/helpers/ArrayHelpers.sol";
import "forge-std/console2.sol";

contract FundFaucetsScript is MigrationHelper {
    using ArrayHelpers for *;

    address public constant FAUCET = 0x0719D47A213149E2Ef8d3f5afDaDA8a8E22dfc03;
    address public constant WALLET_FUNDER = 0x4062E762EC9E2E70f40bd9586C18d1894966628F;
    address public constant FAUCET_CLAIMER = 0x52F09693c9eEaA93A64BA697e3d3e43a1eB65477;
    address public constant KYC_RELAYER = 0x6E31039abF8d248aBed57E307C9E1b7530c269E4;
    address public constant MINT_EOA = 0x6fe642404B7B23F31251103Ca0efb538Ad4aeC07;

    address public constant DINARI = 0xB2eEc63Cdc175d6d07B8f69804C0Ab5F66aCC3cb;
    address public constant KINTO_CORE = 0xD157904639E89df05e89e0DabeEC99aE3d74F9AA;
    address public constant SOCKET_DL = 0x3e9727470C66B1e77034590926CDe0242B5A3dCc;

    function run() public override {
        super.run();

        console2.log("Hot Wallet Balance: %e", deployer.balance);
        if (deployer.balance < 0.25 ether) {
            console2.log("Hot Wallet Balance too low. Refill.");
            return;
        }

        console2.log("");
        console2.log("Faucets");

        address[5] memory faucets = [FAUCET, WALLET_FUNDER, FAUCET_CLAIMER, KYC_RELAYER, MINT_EOA];
        string[5] memory names = ["FAUCET", "WALLET_FUNDER", "FAUCET_CLAIMER", "KYC_RELAYER", "MINT_EOA"];
        uint64[5] memory limits = [0.25 ether, 0.25 ether, 0.25 ether, 0.25 ether, 0.25 ether];
        uint64[5] memory amounts = [0.25 ether, 0.25 ether, 0.25 ether, 0.25 ether, 0.1 ether];

        KintoWalletFactory factory = KintoWalletFactory(_getChainDeployment("KintoWalletFactory"));
        for (uint256 index = 0; index < faucets.length; index++) {
            address faucet = faucets[index];
            uint256 balance = faucet.balance;
            console2.log("Faucet:", names[index]);
            console2.log("Address:", faucets[index]);
            console2.log("Balance: %e", balance);

            if (balance < limits[index]) {
                console2.log("Needs funding. Adding: %e", amounts[index]);

                vm.broadcast(deployerPrivateKey);
                factory.sendMoneyToAccount{value: amounts[index]}(faucet);
            }
        }

        console2.log("");
        console2.log("Apps");

        address[3] memory apps = [KINTO_CORE, DINARI, SOCKET_DL];
        string[3] memory appNames = ["KINTO_CORE", "DINARI", "SOCKET_DL"];
        uint56[3] memory appLimits = [0.05 ether, 0.05 ether, 0.05 ether];
        uint64[3] memory appAmounts = [0.2 ether, 0.2 ether, 0.2 ether];

        SponsorPaymaster paymaster = SponsorPaymaster(_getChainDeployment("SponsorPaymaster"));
        for (uint256 index = 0; index < apps.length; index++) {
            address app = apps[index];
            uint256 balance = paymaster.balances(app);

            console2.log("App:", appNames[index]);
            console2.log("Address:", app);
            console2.log("Balance: %e", balance);

            if (balance < appLimits[index]) {
                console2.log("Needs funding. Adding: %e", appAmounts[index]);

                vm.broadcast(deployerPrivateKey);
                paymaster.addDepositFor{value: appAmounts[index]}(app);
            }
        }
    }
}

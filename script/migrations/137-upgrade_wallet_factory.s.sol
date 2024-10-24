// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import {KintoWalletFactory} from "../../src/wallet/KintoWalletFactory.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract DeployScript is MigrationHelper {
    function run() public override {
        super.run();
        bytes memory bytecode = abi.encodePacked(
            type(KintoWalletFactory).creationCode,
            // wallet address is not used anymore
            abi.encode(
                address(0),
                _getChainDeployment("KintoAppRegistry"),
                _getChainDeployment("KintoID"),
                _getChainDeployment("RewardsDistributor")
            )
        );

        address impl = _deployImplementationAndUpgrade("KintoWalletFactory", "V23", bytecode);

        KintoWalletFactory factory = KintoWalletFactory(_getChainDeployment("KintoWalletFactory"));
        assertEq(address(factory.kintoID()), _getChainDeployment("KintoID"));
        assertEq(address(factory.appRegistry()), _getChainDeployment("KintoAppRegistry"));
        assertEq(address(factory.rewardsDistributor()), _getChainDeployment("RewardsDistributor"));

        saveContractAddress("KintoWalletFactoryV23-impl", impl);

        uint256 LIQUIDITY_MINING_START_DATE = 1718690400; // June 18th 2024

        bytecode = abi.encodePacked(
            type(RewardsDistributor).creationCode,
            abi.encode(
                _getChainDeployment("KINTO"), LIQUIDITY_MINING_START_DATE, _getChainDeployment("KintoWalletFactory")
            )
        );

        impl = _deployImplementationAndUpgrade("RewardsDistributor", "V6", bytecode);

        RewardsDistributor distr = RewardsDistributor(_getChainDeployment("RewardsDistributor"));

        assertEq(address(distr.KINTO()), 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87);
        assertEq(distr.startTime(), LIQUIDITY_MINING_START_DATE);
        assertEq(distr.walletFactory(), _getChainDeployment("KintoWalletFactory"));

        saveContractAddress("RewardsDistributorV6-impl", impl);
    }
}

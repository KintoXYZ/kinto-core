// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";

import "@aa/core/EntryPoint.sol";

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/paymasters/SponsorPaymaster.sol";
import "../../src/KintoID.sol";

import "./Create2Helper.sol";
import "./ArtifactsReader.sol";

abstract contract AASetup is Create2Helper, ArtifactsReader {
    function _checkAccountAbstraction()
        internal
        returns (
            KintoID _kintoID,
            EntryPoint _entryPoint,
            KintoWalletFactory _walletFactory,
            SponsorPaymaster _sponsorPaymaster
        )
    {
        // Kinto ID
        address kintoProxyAddr = _getChainDeployment("KintoID");
        if (!isContract(kintoProxyAddr)) {
            console.log("Kinto ID proxy not deployed at", address(kintoProxyAddr));
            revert("Kinto ID not deployed");
        }
        _kintoID = KintoID(address(kintoProxyAddr));

        // Entry Point
        address entryPointAddr = _getChainDeployment("EntryPoint");
        if (!isContract(entryPointAddr)) {
            console.log("Entry Point not deployed at", address(entryPointAddr));
            revert("Entry Point not deployed");
        }
        _entryPoint = EntryPoint(payable(entryPointAddr));

        // Wallet Factory
        address walletFactoryAddr = _getChainDeployment("KintoWalletFactory");
        if (!isContract(walletFactoryAddr)) {
            console.log("Wallet factory proxy not deployed at", address(walletFactoryAddr));
            revert("Wallet Factory Proxy not deployed");
        }
        _walletFactory = KintoWalletFactory(payable(walletFactoryAddr));

        // Sponsor Paymaster
        address sponsorProxyAddr = _getChainDeployment("SponsorPaymaster");
        if (!isContract(sponsorProxyAddr)) {
            console.log("Paymaster proxy not deployed at", address(sponsorProxyAddr));
            revert("Paymaster proxy not deployed");
        }
        _sponsorPaymaster = SponsorPaymaster(payable(sponsorProxyAddr));
    }
}

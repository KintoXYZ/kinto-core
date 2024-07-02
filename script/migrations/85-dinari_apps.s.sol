// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "../../src/paymasters/SponsorPaymaster.sol";
import "../../src/apps/KintoAppRegistry.sol";
import {console2} from "forge-std/console2.sol";

contract KintoMigration85DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        address dinariWallet = 0x25EA8c663BA8cCd79284B8c4001e7A245071885c;
        address deployer = vm.rememberKey(deployerPrivateKey);
        KintoAppRegistry kintoAppRegistry = KintoAppRegistry(payable(_getChainDeployment("KintoAppRegistry")));
        SponsorPaymaster _paymaster = SponsorPaymaster(payable(_getChainDeployment("SponsorPaymaster")));

        console2.log("wallet factory address", _getChainDeployment("KintoWalletFactory"));
        bytes memory bytecode = abi.encodePacked(
            type(KintoAppRegistryV6).creationCode, abi.encode(address(_getChainDeployment("KintoWalletFactory")))
        );

        _deployImplementationAndUpgrade("KintoAppRegistry", "V6", bytecode);

        // Apps
        console2.log("create apps");

        address parentContract = address(0x400880b800410B2951Afd0503dC457aea8A4bAb5); // Dinari Treasury prod
        address[] memory appContracts = new address[](14);

        // Universal
        appContracts[0] = address(0xF96b974FE330C29e80121E33ed4071C283257979); // dshares rev
        appContracts[1] = address(0xAdFeB630a6aaFf7161E200088B02Cf41112f8B98); // defi ops

        // dshares
        appContracts[2] = address(0xB2eEc63Cdc175d6d07B8f69804C0Ab5F66aCC3cb); // transfer restrictor
        appContracts[3] = address(0xa9a60Ccc6363e440eeEaa8Ad015607c7a34360CE); // DshareBeacon
        appContracts[4] = address(0xd1d93E6Ad5219083Bb2cf3B065a562223381b71F); // WrappedDShareBeacon
        appContracts[5] = address(0xE4Daa69e99F48AD0C4D4843deF4447253248A906); // DShareFactory proxy
        appContracts[6] = address(0x1498A49Ff90d9f7fE8915658A1FC3b87c9A4Ba8c); // Vault
        appContracts[7] = address(0xa089dC07A4baFd941a4323a9078D2c24be8A747C); // Order Processor
        appContracts[8] = address(0x1464727DCC5619E430FaA217a61180d1cEDd2d3a); // Fullfilment router
        appContracts[9] = address(0x8E58548731Ae14D573b54647f2dc393639519fF3); // Dividend Distribution

        // usd+
        appContracts[10] = address(0xd4ee24378201190c7C50D52D3D29C459a1278F91); // transfer restrictor
        appContracts[11] = address(0x6F086dB0f6A621a915bC90295175065c9e5d9b8c); // USD+ Proxy
        appContracts[12] = address(0xeDA274898ED364Bd346fA74cf6eCAB4BF8f1665f); // UsdPlusMinte
        appContracts[13] = address(0x931C5dC9eA13b0F6B4768a98AFfEA773b888e978); // USDPlus Redeeemer

        uint256[4] memory appLimits = [
            kintoAppRegistry.RATE_LIMIT_PERIOD(),
            kintoAppRegistry.RATE_LIMIT_THRESHOLD(),
            kintoAppRegistry.GAS_LIMIT_PERIOD(),
            kintoAppRegistry.GAS_LIMIT_THRESHOLD()
        ];

        vm.startBroadcast(deployerPrivateKey);
        kintoAppRegistry.registerApp("Dinari", parentContract, appContracts, appLimits);
        uint256 tokenID = kintoAppRegistry.getAppMetadata(parentContract).tokenId;
        kintoAppRegistry.safeTransferFrom(deployer, dinariWallet, tokenID);
        _paymaster.addDepositFor{value: 1e16}(parentContract);

        // Stage Dinari
        parentContract = address(0x09E365aCDB0d936DD250351aD0E7de3Dad8706E5); // USD+ treasury stage
        // Contracts
        appContracts[0] = address(0xC60bB79d0176d9C2FD23Eaeff91AC800b3ae5A83); // defi ops

        // dshares
        appContracts[1] = address(0xF34f9C994E28254334C83AcE353d814E5fB90815); // transfer restrictor
        appContracts[2] = address(0x17C477f860aD70541277eF59D5c55aaB0137dbB8); // DshareBeacon
        appContracts[3] = address(0x2e92D8Ba4122a40922BE2B46E01982749d8FC127); // WrappedDShareBeacon
        appContracts[4] = address(0x5fc67f2EE4e30D020A930B745aaDb68DDa985a4C); // DShareFactory proxy
        appContracts[5] = address(0xB621dA3AFC9Df83209042De965dD4Ccb0e8a0ABA); // Vault
        appContracts[6] = address(0x251b1B7c4957FB9Db75921E50F4cf2a5e284b224); // Order Processor
        appContracts[7] = address(0xA4DbdcEFFCbc6141C88F08b3D455775B34218250); // Fullfilment router
        appContracts[8] = address(0xdA25A48456bBdbBe41a03B0D50ba74993A8A0Fa0); // Dividend Distribution

        // usd+
        appContracts[9] = address(0x7031b2EA8B97304885b8c842E14BFc5DD6FC92f8); // transfer restrictor
        appContracts[10] = address(0x0a511eC63c836037F0A2CcC0A81984247E27783b); // USD+ Proxy
        appContracts[11] = address(0xa7D259925f951b674bCDbcF7a63Ab2f5923483dB); // USD+ minter
        appContracts[12] = address(0x2eeBEa5eb4a0feA2ec20FD48A2289D87E2882C71); // USD+ redeemer
        appContracts[13] = address(0x90AB5E52Dfcce749CA062f4e04292fd8a67E86b3); // Mock USDC

        kintoAppRegistry.registerApp("Dinari-stage", parentContract, appContracts, appLimits);
        tokenID = kintoAppRegistry.getAppMetadata(parentContract).tokenId;
        kintoAppRegistry.safeTransferFrom(deployer, dinariWallet, tokenID);
        _paymaster.addDepositFor{value: 1e16}(parentContract);

        vm.stopBroadcast();
        assertEq(kintoAppRegistry.balanceOf(dinariWallet) == 2);
        assertEq(_paymaster.balances(parentContract) == 1e16);
    }
}

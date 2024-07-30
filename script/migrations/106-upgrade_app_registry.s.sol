// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/apps/KintoAppRegistry.sol";
import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "forge-std/console2.sol";

contract DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode =
            abi.encodePacked(type(KintoAppRegistry).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        _deployImplementationAndUpgrade("KintoAppRegistry", "V17", bytecode);

        KintoAppRegistry kintoAppRegistry = KintoAppRegistry(_getChainDeployment("KintoAppRegistry"));

        //TODO: add entrypoints and paymaster on the next hardfork
        address[] memory systemContracts = new address[](21);
        systemContracts[0] = 0xf369f78E3A0492CC4e96a90dae0728A38498e9c7; // kintoIdEnvAddress
        systemContracts[1] = 0x8a4720488CA32f1223ccFE5A087e250fE3BC5D75; // walletFactoryAddress
        systemContracts[2] = 0x5A2b641b84b0230C8e75F55d5afd27f4Dbd59d5b; // appRegistryAddress
        systemContracts[3] = 0x88e03D41a6EAA9A0B93B0e2d6F1B34619cC4319b; // upgradeExecutor
        systemContracts[4] = 0x06FcD8264caF5c28D86eb4630c20004aa1faAaA8; // customGatewayAddress
        systemContracts[5] = 0x340487b92808B84c2bd97C87B590EE81267E04a7; // gatewayRouterAddress
        systemContracts[6] = 0x87799989341A07F495287B1433eea98398FD73aA; // standardGatewayAddress
        systemContracts[7] = 0xd563ECBDF90EBA783d0a218EFf158C1263ad02BE; // wethGateWayAddress
        systemContracts[8] = 0x8d2D899402ed84b6c0510bB1ad34ee436ADDD20d; // bundleBulker
        systemContracts[9] = 0x000000000000000000000000000000000000006E; // arbRetrayableTx
        systemContracts[10] = 0x3e9727470C66B1e77034590926CDe0242B5A3dCc; // socket-dl
        systemContracts[11] = 0x6c914cc610e9a05eaFFfD79c10c60Ad1704717E5; // socketExecutionManager
        systemContracts[12] = 0x6332e56A423480A211E301Cb85be12814e9238Bb; // socketTransmitManager
        systemContracts[13] = 0x516302D1b25e5F6d1ac90eF7256270cd799524CF; // socketFastSwitchboard
        systemContracts[14] = 0x2B98775aBE9cDEb041e3c2E56C76ce2560AF57FB; // socketOptimisticSwitchboard
        systemContracts[15] = 0x12FF8947a2524303C13ca7dA9bE4914381f6557a; // socketBatcher
        systemContracts[16] = 0x72846179EF1467B2b71F2bb7525fcD4450E46B2A; // socketSimulator
        systemContracts[17] = 0x897DA4D039f64090bfdb33cd2Ed2Da81adD6FB02; // socketSimulatorUtils
        systemContracts[18] = 0xa7527C270f30cF3dAFa6e82603b4978e1A849359; // socketSwitchboardSimulator
        systemContracts[19] = 0x6dbB5ee7c63775013FaF810527DBeDe2810d7Aee; // socketCapacitorSimulator
        systemContracts[20] = 0x4e59b44847b379578588920cA78FbF26c0B4956C; // create2Factory
        kintoAppRegistry.updateSystemContracts(systemContracts);

        address[] memory reservedContracts = new address[](13);
        reservedContracts[0] = 0x2843C269D2a64eCfA63548E8B3Fc0FD23B7F70cb; // aaEntryPointEnvAddress
        reservedContracts[1] = 0x0000000071727De22E5E9d8BAf0edAc6f37da032; // aaEntryPointEnvAddressV7
        reservedContracts[2] = 0x4e59b44847b379578588920cA78FbF26c0B4956C; // create2Factory
        reservedContracts[3] = 0xf369f78E3A0492CC4e96a90dae0728A38498e9c7; // kintoIdEnvAddress
        reservedContracts[4] = 0x8a4720488CA32f1223ccFE5A087e250fE3BC5D75; // walletFactoryAddress
        reservedContracts[5] = 0x1842a4EFf3eFd24c50B63c3CF89cECEe245Fc2bd; // paymasterAddress
        reservedContracts[6] = 0x5A2b641b84b0230C8e75F55d5afd27f4Dbd59d5b; // appRegistryAddress
        reservedContracts[7] = 0x88e03D41a6EAA9A0B93B0e2d6F1B34619cC4319b; // upgradeExecutor
        reservedContracts[8] = 0x06FcD8264caF5c28D86eb4630c20004aa1faAaA8; // customGatewayAddress
        reservedContracts[9] = 0x340487b92808B84c2bd97C87B590EE81267E04a7; // gatewayRouterAddress
        reservedContracts[10] = 0x87799989341A07F495287B1433eea98398FD73aA; // standardGatewayAddress
        reservedContracts[11] = 0xd563ECBDF90EBA783d0a218EFf158C1263ad02BE; // wethGateWayAddress
        reservedContracts[12] = 0x8d2D899402ed84b6c0510bB1ad34ee436ADDD20d; // bundleBulker
        reservedContracts[13] = 0x000000000000000000000000000000000000006E; // arbRetrayableTx

        kintoAppRegistry.updateReservedContracts(reservedContracts);
    }
}


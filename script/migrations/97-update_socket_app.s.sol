// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoAppRegistry, KintoAppRegistryV9} from "@kinto-core/apps/KintoAppRegistry.sol";

contract KintoMigration97DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(
            type(KintoAppRegistryV9).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory"))
        );
        _deployImplementationAndUpgrade("KintoAppRegistry", "V9", bytecode);

        KintoAppRegistry kintoAppRegistry = KintoAppRegistry(payable(_getChainDeployment("KintoAppRegistry")));

        address parentContract = address(0x3e9727470C66B1e77034590926CDe0242B5A3dCc); // Socket-DL contract
        address[] memory appContracts = new address[](19);

        // controllers
        appContracts[0] = address(0xaBc64E84c653e0f077c0178E4b1fAC01Bfcc20b0); // DAI controller
        appContracts[1] = address(0xDB09c7C2C4071e3Ca1bAD0C357906Efa17c25102); // wstETH controller
        appContracts[2] = address(0x7D4E3628C3DEce7bA053c296eEA3729318F93715); // WETH controller
        appContracts[3] = address(0xFe6E2862ef74ADF306AAcd575eAF5F45281B1017); // USDC controller
        appContracts[4] = address(0x342f5BA3230f6D1E32Aa775440BDcB93647dD4CD); // ENA controller
        appContracts[5] = address(0x4c9c64B2FAe0e13dF9A635ad699c5eFC386D1Cee); // USDe controller
        appContracts[6] = address(0x345B2061EA8256689349fca968CF7Af0Ff6011Aa); // EIGEN controller
        appContracts[7] = address(0x8D23e5Ba32Ca80809d60eD70ddbd96e6b3D61015); // eETH controller
        appContracts[8] = address(0x28A6468dE32690f63D8095e8980B43ab48F9470C); // sDAI controller
        appContracts[9] = address(0xCE2FC6C6bFCF04f2f857338ecF6004381F414926); // sUSDe controller
        appContracts[10] = address(0xe3F4C9cCA8eA855497D63800beFb43f290aC78c6); // wUSDM controller
        appContracts[11] = address(0xC7FCA8aB6D1E1142790454e7e5655d93c3b03ed6); // weETH controller
        appContracts[12] = address(0x24f287b474a05E48627846148cCdA3D05de03953); // ETHFI controller
        appContracts[13] = address(0xA2a13094baB725D6D9dd8b9B5c01F1a1bF67F986); // SolvBTC controller
        appContracts[14] = address(0x90128652cF49A44F0374d0EE7d3782df59e72A8C); // MKR controller
        appContracts[15] = address(0xd17b43d94f0BF2960d285E89de5b9a8369e3eD5b); // PAXG controller
        appContracts[16] = address(0xf5d3d976872E01b7B7aF7964Ca9cf4D992584726); // XAUT controller
        appContracts[17] = address(0x7DA5691fB59740cF02CC7dc16743Be9dCBf685b5); // stUSD controller
        appContracts[18] = address(0xe5b6205CfC03786Fc554c40767A591b8dCBC1E76); // stEUR controller

        uint256[4] memory appLimits = [
            kintoAppRegistry.RATE_LIMIT_PERIOD(),
            kintoAppRegistry.RATE_LIMIT_THRESHOLD(),
            kintoAppRegistry.GAS_LIMIT_PERIOD(),
            kintoAppRegistry.GAS_LIMIT_THRESHOLD()
        ];

        address[] memory systemContracts = new address[](1);
        systemContracts[0] = 0x12FF8947a2524303C13ca7dA9bE4914381f6557a; // Socket Batcher

        // Socket-batcher app
        address[] memory batcherEOAs = new address[](4);
        batcherEOAs[0] = address(0x090FC3eaD2E5e81d3c0FA2E45636Ef003baB9DFB);
        batcherEOAs[1] = address(0xA214AED7Cf1982D5e342Fd93711a49153623f953);
        batcherEOAs[2] = address(0x07ca54b301dECA9C8Bc9AF4e4Cd6A87531018031);
        batcherEOAs[3] = address(0xD1D6634415Be11A54664298373C57c131aA828d5);

        vm.startBroadcast(deployerPrivateKey);
        kintoAppRegistry.registerApp(
          "Socket-batcher", 0x12FF8947a2524303C13ca7dA9bE4914381f6557a, new address[](0), appLimits, batcherEOAs
        );
        kintoAppRegistry.updateMetadata("Socket", parentContract, appContracts, appLimits, new address[](0));

        vm.stopBroadcast();
        _handleOps(
            abi.encodeWithSelector(
                KintoAppRegistry.updateSystemContracts.selector,
                systemContracts
            ),
            address(_getChainDeployment("KintoAppRegistry"))
        );
        assertEq(kintoAppRegistry.isSystemContract(systemContracts[0]), true);
    }
}

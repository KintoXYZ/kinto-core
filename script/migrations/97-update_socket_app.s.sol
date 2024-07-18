// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoAppRegistry, KintoAppRegistryV10} from "@kinto-core/apps/KintoAppRegistry.sol";

contract KintoMigration97DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(
            type(KintoAppRegistryV10).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory"))
        );
        _deployImplementationAndUpgrade("KintoAppRegistry", "V10", bytecode);

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
        address[] memory batcherEOAs = new address[](21);
        batcherEOAs[0] = address(0x090FC3eaD2E5e81d3c0FA2E45636Ef003baB9DFB);
        batcherEOAs[1] = address(0xA214AED7Cf1982D5e342Fd93711a49153623f953);
        batcherEOAs[2] = address(0x07ca54b301dECA9C8Bc9AF4e4Cd6A87531018031);
        batcherEOAs[3] = address(0x78246aC69cce0d90A366B2d52064a88bb4aD8467);
        batcherEOAs[4] = address(0x1612Ba11DC7Df706b20CD1f10485a401510b733D);
        batcherEOAs[5] = address(0x023C34fb3Ed5880C865CF918774Ca12440dcB8BE);
        batcherEOAs[6] = address(0xe57F05B668a660730c6E53e7219dAaEE816c6A42);
        batcherEOAs[7] = address(0xf46b7b71Bf024c4a7A102FB570C89b03d3dDEc92);
        batcherEOAs[8] = address(0xBc8b8f4e21d51DBdCD0E453d7D689ccb0D3e2B7b);
        batcherEOAs[9] = address(0x54d3FD4D39Dbdc19cd5D1f7C768bFd64b9b083Fa);
        batcherEOAs[10] = address(0x3dD9202eEF026d70fA941aaDec376D334c264655);
        batcherEOAs[11] = address(0x7cD375aB19061bD3b5Ae28912883AaBE8108b633);
        batcherEOAs[12] = address(0x6fB68De2F072f720BDAc80E8BCe9D124E44c33a5);
        batcherEOAs[13] = address(0xdE4e383CaF7659C08AbC3Ce29539D8CA22ee9c71);
        batcherEOAs[14] = address(0xeD85Fa16FE6bF65CEf63a7FCa08f2366Dc224Dd4);
        batcherEOAs[15] = address(0x26cE14a363Cd7D52A02B996dbaC9d7eF47E46662);
        batcherEOAs[16] = address(0xB49d1bC43e1Ae7081eF8eFc1B550C85e057da558);
        batcherEOAs[17] = address(0xb6799BaEE97CF905D50DBD296c4e26253751eBd1);
        batcherEOAs[18] = address(0xE83141Cc5A9d04b0F8b2A98cD32c27E0FCBa2Dd4);
        batcherEOAs[19] = address(0x5A4c33DC6c8a53cb1Ba989eE62dcaE09036C7682);
        batcherEOAs[20] = address(0xD1D6634415Be11A54664298373C57c131aA828d5);

        vm.startBroadcast(deployerPrivateKey);
        kintoAppRegistry.registerApp(
            "Socket-batcher", 0x12FF8947a2524303C13ca7dA9bE4914381f6557a, new address[](0), appLimits, batcherEOAs
        );
        kintoAppRegistry.updateMetadata("Socket", parentContract, appContracts, appLimits, new address[](0));

        vm.stopBroadcast();
        _handleOps(
            abi.encodeWithSelector(KintoAppRegistry.updateSystemContracts.selector, systemContracts),
            address(_getChainDeployment("KintoAppRegistry"))
        );
        assertEq(kintoAppRegistry.isSystemContract(systemContracts[0]), true);
    }
}

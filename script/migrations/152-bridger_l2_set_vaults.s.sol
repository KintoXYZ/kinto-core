// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/bridger/BridgerL2.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "forge-std/console2.sol";
import "@kinto-core-test/helpers/ArrayHelpers.sol";

contract Script is MigrationHelper {
    using ArrayHelpers for *;

    address[] internal vaults;
    bool[] internal flags;

    function run() public override {
        super.run();

        vaults.push(0xaBc64E84c653e0f077c0178E4b1fAC01Bfcc20b0);
        vaults.push(0xDB09c7C2C4071e3Ca1bAD0C357906Efa17c25102);
        vaults.push(0x7D4E3628C3DEce7bA053c296eEA3729318F93715);
        vaults.push(0xFe6E2862ef74ADF306AAcd575eAF5F45281B1017);
        vaults.push(0x342f5BA3230f6D1E32Aa775440BDcB93647dD4CD);
        vaults.push(0x4c9c64B2FAe0e13dF9A635ad699c5eFC386D1Cee);
        vaults.push(0x345B2061EA8256689349fca968CF7Af0Ff6011Aa);
        vaults.push(0x8D23e5Ba32Ca80809d60eD70ddbd96e6b3D61015);
        vaults.push(0x28A6468dE32690f63D8095e8980B43ab48F9470C);
        vaults.push(0xCE2FC6C6bFCF04f2f857338ecF6004381F414926);
        vaults.push(0xe3F4C9cCA8eA855497D63800beFb43f290aC78c6);
        vaults.push(0xC7FCA8aB6D1E1142790454e7e5655d93c3b03ed6);
        vaults.push(0x24f287b474a05E48627846148cCdA3D05de03953);
        vaults.push(0xA2a13094baB725D6D9dd8b9B5c01F1a1bF67F986);
        vaults.push(0xE1857425c14afe4142cE4df1eCb3439f194d5D1b);
        vaults.push(0x90128652cF49A44F0374d0EE7d3782df59e72A8C);
        vaults.push(0xd17b43d94f0BF2960d285E89de5b9a8369e3eD5b);
        vaults.push(0xf5d3d976872E01b7B7aF7964Ca9cf4D992584726);
        vaults.push(0x7DA5691fB59740cF02CC7dc16743Be9dCBf685b5);
        vaults.push(0xe5b6205CfC03786Fc554c40767A591b8dCBC1E76);
        vaults.push(0xa968C2771d5E984979589ef8f6fA59D5818a208F);
        vaults.push(0xbBA40ecf76e13219D3b17B730a4be2136918E91E);
        vaults.push(0x9119d9D07FF1fEB8cd902A05603f6596D4A0d754);
        vaults.push(0x50291565834df33346103e1Ff1dd5e0B19402443);
        vaults.push(0xaE7f260b74f289ab3701fb01Cbf81bCD76454222);
        vaults.push(0x5324a41FaC86C0D6CD301B3144124fD3c399Fd87);
        vaults.push(0x04481a364aCfD0776a30a6731D9Ee5425b9300EA);
        vaults.push(0xd0d4cDB49DDa0F9B4785B3823eEdaA84B84afAd9);
        vaults.push(0x19E5C67db27284907978F4Fd856403346816BF87);
        vaults.push(0x5f40795576557877d0fEd93b5A9ea8a195924862);
        vaults.push(0x2d82862810e1B040B8EA419dc309572364E574e7);
        vaults.push(0x45113356a5b8b1ba8A8Bc75dcAAc42bE06663880);
        vaults.push(0x8cd4725D32CcFB201A25F1E1a18260E53F37C927);
        vaults.push(0xB0FC8B7fb66958fe813475bBDC91c1Ac75725442);
        vaults.push(0xCa7e797319B83A3d7bc9Ac18E449E9dF9E2BA547);
        vaults.push(0xd1Dae5b7256Fe762EdAbDa7ff051F036A868B4f7);
        vaults.push(0xE897Bdc146f5f2C986d547D07E6Da55074fCcD7B);
        vaults.push(0x7799B5f05d75DecE15d85507875879cedc62e16E);
        vaults.push(0x0B61E51cbcfd6a9F7A03c413731B0BBB378EB6d4);
        vaults.push(0xC27a019Dd349c52B0Af2195303D3Cd0528eD29dC);

        for (uint256 index = 0; index < vaults.length; index++) {
            flags.push(true);
        }
        _handleOps(
            abi.encodeWithSelector(BridgerL2.setBridgeVault.selector, vaults, flags), _getChainDeployment("BridgerL2")
        );
    }
}

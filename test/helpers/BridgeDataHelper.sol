// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";

import "@kinto-core/interfaces/bridger/IBridger.sol";
import "@kinto-core/bridger/Bridger.sol";

import "@kinto-core-test/fork/const.sol";
import "@kinto-core-test/helpers/UUPSProxy.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/harness/BridgerHarness.sol";
import "@kinto-core-test/helpers/ArtifactsReader.sol";
import {ForkTest} from "@kinto-core-test/helpers/ForkTest.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import "@kinto-core/interfaces/bridger/IBridger.sol";
import "@kinto-core/bridger/Bridger.sol";

import "forge-std/console2.sol";

abstract contract BridgeDataHelper is Constants {
    // chainid => asset => bridger data
    mapping(uint256 => mapping(address => IBridger.BridgeData)) internal bridgeData;

    IBridger.BridgeData internal emptyBridgerData;

    constructor() {
        emptyBridgerData = IBridger.BridgeData({
            vault: address(0),
            gasFee: 0,
            msgGasLimit: 0,
            connector: address(0),
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ETHEREUM_CHAINID][wstETH_ETHEREUM] = IBridger.BridgeData({
            vault: 0xc5d01939Af7Ce9Ffc505F0bb36eFeDde7920f2dc,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0x83C6d6597891Ad48cF5e0BA901De55120C37C6bE,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ETHEREUM_CHAINID][WETH_ETHEREUM] = IBridger.BridgeData({
            vault: 0xeB66259d2eBC3ed1d3a98148f6298927d8A36397,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0xE2c2291B80BFC8Bd0e4fc8Af196Ae5fc9136aeE0,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ETHEREUM_CHAINID][sDAI_ETHEREUM] = IBridger.BridgeData({
            vault: 0x5B8Ae1C9c5970e2637Cf3Af431acAAebEf7aFb85,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0xF5992B6A0dEa32dCF6BE7bfAf762A4D94f139Ea7,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ETHEREUM_CHAINID][sUSDe_ETHEREUM] = IBridger.BridgeData({
            vault: 0x43b718Aa5e678b08615CA984cbe25f690B085b32,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0xE274dB6b891159547FbDC18b07412EE7F4B8d767,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ETHEREUM_CHAINID][ENA_ETHEREUM] = IBridger.BridgeData({
            vault: 0x351d8894fB8bfa1b0eFF77bFD9Aab18eA2da8fDd,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0x266abd77Da7F877cdf93c0dd5782cC61Fa29ac96,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ARBITRUM_CHAINID][WETH_ARBITRUM] = IBridger.BridgeData({
            vault: 0x4D585D346DFB27b297C37F480a82d4cAB39491Bb,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0x47469683AEAD0B5EF2c599ff34d55C3D998393Bf,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ARBITRUM_CHAINID][wUSDM] = IBridger.BridgeData({
            vault: 0x500c8337782a9f82C5376Ea71b66A749cE42b507,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0xe5FA8E712B8932AdBB3bcd7e1d49Ea1E7cC0F58D,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ARBITRUM_CHAINID][SOLV_BTC_ARBITRUM] = IBridger.BridgeData({
            vault: 0x25a1baC7314Ff40Ee8CD549251924D066D7d5bC6,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0x5817bF28f6f0B0215f310837BAB88A127d29aBF3,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ARBITRUM_CHAINID][stUSD] = IBridger.BridgeData({
            vault: 0x97bf1f0F7A929bE866F7Fbeb35545f5429Addf26,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0xE16Cc29f4d28BB93D1B882035D87dE9AC0306bAd,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ARBITRUM_CHAINID][USDC_ARBITRUM] = IBridger.BridgeData({
            vault: 0xC88A469B96A62d4DA14Dc5e23BDBC495D2b15C6B,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0xD97E3cD27fb8af306b2CD42A61B7cbaAF044D08D,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ARBITRUM_CHAINID][DAI_ARBITRUM] = IBridger.BridgeData({
            vault: 0x36E2DBe085eE4d028fD60f70670f662365d0E978,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0x4b7945796aFe4d2fCe6D271bF7773b5163E1bcC1,
            execPayload: bytes(""),
            options: bytes("")
        });

        bridgeData[ARBITRUM_CHAINID][A_ARB_USDC_ARBITRUM] = IBridger.BridgeData({
            vault: 0xF0e641380480E4794F9cBecDA88E7411626174DF,
            gasFee: 1e16,
            msgGasLimit: 500_000,
            connector: 0xB1b7BC699cAEcB941e7377065c7CE82039889603,
            execPayload: bytes(""),
            options: bytes("")
        });
    }
}

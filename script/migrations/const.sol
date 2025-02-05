// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {CommonBase} from "forge-std/Base.sol";

contract Constants is CommonBase {
    uint256 internal constant LEDGER = 0;
    uint256 internal constant TREZOR = 1;

    uint256 internal constant KINTO_CHAINID = 7887;
    uint256 internal constant BASE_CHAINID = 8453;
    uint256 internal constant ARBITRUM_CHAINID = 42161;
    uint256 internal constant ETHEREUM_CHAINID = 1;

    address internal constant WUSDM = 0x57F5E098CaD7A3D1Eed53991D4d66C45C9AF7812; // wUSDM

    uint64 internal constant NIO_GOVERNOR_ROLE = uint64(uint256(keccak256("NIO_GOVERNOR_ROLE")));
    uint64 internal constant UPGRADER_ROLE = uint64(uint256(keccak256("UPGRADER_ROLE")));
    uint32 internal constant NIO_EXECUTION_DELAY = 3 days;
    uint32 internal constant ACCESS_REGISTRY_DELAY = 16 hours;
    uint32 internal constant UPGRADE_DELAY = 7 days;
    uint256 internal constant RATE_LIMIT_PERIOD = 1 minutes;
    uint256 internal constant RATE_LIMIT_THRESHOLD = 10;
    uint256 internal constant GAS_LIMIT_PERIOD = 30 days;
    uint256 internal constant GAS_LIMIT_THRESHOLD = 0.01 ether;

    address internal constant ARB_AAVE_POOL_PROVIDER = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;
    address internal constant BASE_AAVE_POOL_PROVIDER = 0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D;
    address internal constant ETHEREUM_AAVE_POOL_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address payable internal constant ENTRY_POINT = payable(0x0000000071727De22E5E9d8BAf0edAc6f37da032);

    function getAavePoolProvider() internal view returns (address) {
        if (block.chainid == ARBITRUM_CHAINID) return ARB_AAVE_POOL_PROVIDER;
        if (block.chainid == BASE_CHAINID) return BASE_AAVE_POOL_PROVIDER;
        if (block.chainid == ETHEREUM_CHAINID) return ETHEREUM_AAVE_POOL_PROVIDER;
        revert("No Aave pool provider for current chain");
    }

    function getMamoriSafeByChainId(uint256 chainid) public view returns (address) {
        // mainnet
        if (chainid == 1) {
            return 0xf152Abda9E4ce8b134eF22Dc3C6aCe19C4895D82;
        }
        // base
        if (chainid == 8453) {
            return 0x45e9deAbb4FdD048Ae38Fce9D9E8d68EC6f592a2;
        }
        // arbitrum one
        if (chainid == 42161) {
            return 0x8bFe32Ac9C21609F45eE6AE44d4E326973700614;
        }
        revert(string.concat("No Safe address for chainid:", vm.toString(block.chainid)));
    }

    function getWethByChainId(uint256 chainid) public view returns (address) {
        // local
        if (chainid == 31337) {
            return 0x4200000000000000000000000000000000000006;
        }
        // mainnet
        if (chainid == 1) {
            return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        }
        // base
        if (chainid == 8453) {
            return 0x4200000000000000000000000000000000000006;
        }
        // arbitrum one
        if (chainid == 42161) {
            return 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        }
        // optimism
        if (chainid == 10) {
            return 0x4200000000000000000000000000000000000006;
        }
        revert(string.concat("No WETH address for chainid:", vm.toString(block.chainid)));
    }
}

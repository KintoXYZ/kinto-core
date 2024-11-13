// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract Constants {
    uint256 internal constant LEDGER = 0;
    uint256 internal constant TREZOR = 1;

    uint256 internal constant BASE_CHAINID = 8453;
    uint256 internal constant ARBITRUM_CHAINID = 42161;
    uint256 internal constant ETHEREUM_CHAINID = 1;

    address internal constant WUSDM = 0x57F5E098CaD7A3D1Eed53991D4d66C45C9AF7812; // wUSDM

    uint64 internal constant NIO_GOVERNOR_ROLE = uint64(uint256(keccak256("NIO_GOVERNOR_ROLE")));
    uint256 internal constant NIO_EXECUTION_DELAY = 3 days;
    uint256 internal constant RATE_LIMIT_PERIOD = 1 minutes;
    uint256 internal constant RATE_LIMIT_THRESHOLD = 10;
    uint256 internal constant GAS_LIMIT_PERIOD = 30 days;
    uint256 internal constant GAS_LIMIT_THRESHOLD = 0.01 ether;

    address internal constant ARB_AAVE_POOL_PROVIDER = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;
    address internal constant BASE_AAVE_POOL_PROVIDER = 0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D;
    address internal constant ETHEREUM_AAVE_POOL_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;

    function getAavePoolProvider() internal view returns (address) {
        if (block.chainid == ARBITRUM_CHAINID) return ARB_AAVE_POOL_PROVIDER;
        if (block.chainid == BASE_CHAINID) return BASE_AAVE_POOL_PROVIDER;
        if (block.chainid == ETHEREUM_CHAINID) return ETHEREUM_AAVE_POOL_PROVIDER;
        revert("No Aave pool provider for current chain");
    }
}

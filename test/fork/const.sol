// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract Constants {
    uint256 internal constant BASE_CHAINID = 8453;
    uint256 internal constant ARBITRUM_CHAINID = 42161;
    uint256 internal constant ETHEREUM_CHAINID = 1;

    address internal constant EXCHANGE_PROXY = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    address internal constant WETH_ETHEREUM = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI_ETHEREUM = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant DAI_ARBITRUM = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address internal constant USDe_ETHEREUM = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address internal constant sUSDe_ETHEREUM = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address internal constant wstETH_ETHEREUM = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant sDAI_ETHEREUM = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address internal constant ENA_ETHEREUM = 0x57e114B691Db790C35207b2e685D4A43181e6061;
    address internal constant USDM_CURVE_POOL_ARBITRUM = 0x4bD135524897333bec344e50ddD85126554E58B4;
    address internal constant USDC_ARBITRUM = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address internal constant WBTC_ARBITRUM = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address internal constant SOLV_BTC_ARBITRUM = 0x3647c54c4c2C65bC7a2D63c0Da2809B399DBBDC0;

    /// @notice The address of the USDM token. The same on all chains.
    address public constant USDM = 0x59D9356E565Ab3A36dD77763Fc0d87fEaf85508C;
    /// @notice The address of the wrapped USDM token. The same on all chains.
    address public constant wUSDM = 0x57F5E098CaD7A3D1Eed53991D4d66C45C9AF7812;
    /// @notice stUSD pool id on Arbitrum.
    address public constant stUSD = 0x0022228a2cc5E7eF0274A7Baa600d44da5aB5776;
    /// @notice USDA pool id on Arbitrum.
    address public constant USDA = 0x0000206329b97DB379d5E1Bf586BbDB969C63274;
}

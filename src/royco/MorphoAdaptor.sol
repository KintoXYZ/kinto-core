// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import {Id, IMorpho, MarketParams} from "@kinto-core/interfaces/external/IMorpho.sol";
import {IPreLiquidationFactory} from "@kinto-core/interfaces/external/IMorphoPreLiquidationFactory.sol";
import {IPreLiquidation, PreLiquidationParams} from "@kinto-core/interfaces/external/IMorphoPreLiquidation.sol";
import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";

/**
 * @title MorphoRoycoAdaptor
 * @notice Allows interacting with Morpho protocol for lending and borrowing operations via Royco
 * @dev Provides functions to supply and withdraw from Kinto Morpho markets on Arbitrum
 */
contract MorphoRoycoAdaptor {
    using SafeERC20 for IERC20;
    using Address for address;

    /* ============ Constants ============ */

    /// @notice Address of the Morpho protocol on Arbitrum
    address public constant MORPHO = 0x6c247b1F6182318877311737BaC0844bAa518F5e;

    /// @notice Loan token (USDC.e on Arbitrum)
    address public constant LOAN_TOKEN = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    /// @notice Collateral token ($K on Arbitrum)
    address public constant COLLATERAL_TOKEN = 0x010700AB046Dd8e92b0e3587842080Df36364ed3;

    /// @notice Oracle address
    address public constant ORACLE = 0x2964aB84637d4c3CAF0Fd968be1c97D9990de925;

    /// @notice Interest Rate Model
    address public constant IRM = 0x66F30587FB8D4206918deb78ecA7d5eBbafD06DA;

    /// @notice Liquidation Loan-to-Value (62.5%)
    uint256 public constant LLTV = 625000000000000000;

    /// @notice Address of the pre-liquidation contract
    address public constant PRE_LIQUIDATION = 0xdE616CeEF394f5E05ed8b6cABa83cBBCC60C0640;

    /// @notice Address of the bridger contract
    address public constant BRIDGER = 0xb7DfE09Cf3950141DFb7DB8ABca90dDef8d06Ec0;

    mapping(address => uint256) public walletBalances;

    /* ============ Internal Functions ============ */

    /**
     * @notice Creates the MarketParams struct for Morpho operations
     * @return The MarketParams struct for Morpho operations
     */
    function _getMarketParams() internal pure returns (MarketParams memory) {
        return MarketParams({
            loanToken: LOAN_TOKEN,
            collateralToken: COLLATERAL_TOKEN,
            oracle: ORACLE,
            irm: IRM,
            lltv: LLTV
        });
    }

    /// @notice The length of the data used to compute the id of a market.
    /// @dev The length is 5 * 32 because `MarketParams` has 5 variables of 32 bytes each.
    uint256 internal constant MARKET_PARAMS_BYTES_LENGTH = 5 * 32;

    /**
     * @notice Calculates the unique ID for a market based on its parameters
     * @dev Uses keccak256 hash of the packed market parameters
     * @param marketParams The market parameters struct
     * @return marketParamsId The unique identifier for the market
     */
    function id(MarketParams memory marketParams) public pure returns (Id marketParamsId) {
        assembly ("memory-safe") {
            marketParamsId := keccak256(marketParams, MARKET_PARAMS_BYTES_LENGTH)
        }
    }

    /* ============ External Functions ============ */

    /**
     * @notice Supplies assets to Morpho protocol
     * @dev Supplies loan tokens (USDC.e) to the Morpho market
     * @param amountSupply The amount of USDC to supply
     * @return suppliedShares The amount of shares received
     */
    function supply(uint256 amountSupply) external returns (uint256 suppliedShares) {
        // Get market params
        MarketParams memory marketParams = _getMarketParams();

        // Transfer from wallet
        IERC20(LOAN_TOKEN).safeTransferFrom(msg.sender, address(this), amountSupply);

        // Approve Morpho to spend tokens
        IERC20(LOAN_TOKEN).forceApprove(MORPHO, amountSupply);

        // Supply to Morpho
        (, suppliedShares) = IMorpho(MORPHO).supply(marketParams, amountSupply, 0, address(this), "");

        walletBalances[msg.sender] += suppliedShares;

        return suppliedShares;
    }

    /**
     * @notice Withdraws assets from Morpho protocol and bridges them to a Royco wallet
     * @dev Withdraws loan tokens (USDC.e) from the Morpho market and sends them to a specified wallet
     * @param sharesWithdraw The amount of shares to withdraw
     */
    function withdraw(uint256 sharesWithdraw) external {
        uint256 balance = walletBalances[msg.sender];

        if (balance < sharesWithdraw) {
            revert("Insufficient balance");
        }

        // Get market params
        MarketParams memory marketParams = _getMarketParams();

        walletBalances[msg.sender] -= sharesWithdraw;
        // Withdraw from Morpho
        IMorpho(MORPHO).withdraw(marketParams, 0, sharesWithdraw, address(this), msg.sender);
    }
}

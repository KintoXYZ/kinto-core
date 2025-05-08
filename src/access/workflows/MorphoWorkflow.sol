// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import {Id, IMorpho, MarketParams} from "@kinto-core/interfaces/external/IMorpho.sol";

/**
 * @title MorphoWorkflow
 * @notice Allows interacting with Morpho protocol for lending and borrowing operations
 */
contract MorphoWorkflow {
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

    /* ============ External Functions ============ */

    /**
     * @notice Supplies collateral and optionally borrows loan tokens
     * @param amountLend The amount of collateral tokens to lend
     * @param amountBorrow The amount of loan tokens to borrow (can be 0)
     * @return borrowed The amount of loan tokens borrowed
     */
    function lendAndBorrow(uint256 amountLend, uint256 amountBorrow) external returns (uint256 borrowed) {
        // Get market params
        MarketParams memory marketParams = _getMarketParams();

        // Approve Morpho to spend collateral tokens
        IERC20(COLLATERAL_TOKEN).forceApprove(MORPHO, amountLend);

        // Supply collateral to Morpho
        IMorpho(MORPHO).supplyCollateral(marketParams, amountLend, address(this), "");

        // If amountBorrow > 0, borrow loan tokens
        if (amountBorrow > 0) {
            // Borrow loan tokens from Morpho
            (borrowed,) = IMorpho(MORPHO).borrow(marketParams, amountBorrow, 0, address(this), address(this));
        }

        return borrowed;
    }

    /**
     * @notice Repays loan and optionally withdraws collateral
     * @param amountRepay The amount of loan tokens to repay (can be 0)
     * @param amountWithdraw The amount of collateral tokens to withdraw
     * @return withdrawn The amount of collateral tokens withdrawn
     */
    function repayAndWithdraw(uint256 amountRepay, uint256 amountWithdraw) external returns (uint256 withdrawn) {
        // Get market params
        MarketParams memory marketParams = _getMarketParams();

        // If amountRepay > 0, repay loan
        if (amountRepay > 0) {
            // Approve Morpho to spend loan tokens
            IERC20(LOAN_TOKEN).forceApprove(MORPHO, amountRepay);

            // Repay loan to Morpho
            IMorpho(MORPHO).repay(marketParams, amountRepay, 0, address(this), "");
        }

        // Withdraw collateral from Morpho
        if (amountWithdraw > 0) {
            IMorpho(MORPHO).withdrawCollateral(marketParams, amountWithdraw, address(this), address(this));
            withdrawn = amountWithdraw;
        }

        return withdrawn;
    }

    /**
     * @notice Supplies assets to Morpho protocol
     * @param amountSupply The amount of assets to supply
     * @return supplied The amount of assets supplied
     */
    function supply(uint256 amountSupply) external returns (uint256 supplied) {
        // Get market params
        MarketParams memory marketParams = _getMarketParams();

        // Approve Morpho to spend tokens
        IERC20(LOAN_TOKEN).forceApprove(MORPHO, amountSupply);

        // Supply to Morpho
        (supplied,) = IMorpho(MORPHO).supply(marketParams, amountSupply, 0, address(this), "");

        return supplied;
    }

    /**
     * @notice Withdraws assets from Morpho protocol
     * @param amountWithdraw The amount of assets to withdraw
     * @return withdrawn The amount of assets withdrawn
     */
    function withdraw(uint256 amountWithdraw) external returns (uint256 withdrawn) {
        // Get market params
        MarketParams memory marketParams = _getMarketParams();

        // Withdraw from Morpho
        (withdrawn,) = IMorpho(MORPHO).withdraw(marketParams, amountWithdraw, 0, address(this), address(this));

        return withdrawn;
    }
}

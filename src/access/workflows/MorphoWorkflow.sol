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
 * @title MorphoWorkflow
 * @notice Allows interacting with Morpho protocol for lending and borrowing operations
 * @dev Provides functions to lend, borrow, repay, and withdraw from Morpho markets on Arbitrum
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

    /// @notice Address of the pre-liquidation contract
    address public constant PRE_LIQUIDATION = 0xdE616CeEF394f5E05ed8b6cABa83cBBCC60C0640;

    /// @notice Address of the bridger contract
    address public constant BRIDGER = 0xb7DfE09Cf3950141DFb7DB8ABca90dDef8d06Ec0;

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
     * @notice Supplies collateral tokens to the Morpho market without borrowing
     * @dev This is a simplified version of lendAndBorrow with zero borrow amount
     * @param amountLend The amount of collateral tokens to lend
     */
    function lend(uint256 amountLend) public {
        lendAndBorrow(
            amountLend,
            0, // amountBorrow = 0
            address(0), // kintoWallet = zero
            IBridger.BridgeData({ // empty “zero” BridgeData:
                vault: address(0),
                gasFee: 0,
                msgGasLimit: 0,
                connector: address(0),
                execPayload: bytes(""), // or new bytes(0)
                options: bytes("") // or new bytes(0)
            })
        );
    }

    /**
     * @notice Supplies collateral and optionally borrows loan tokens
     * @dev Creates pre-liquidation contract if not already set up, and bridges borrowed assets if requested
     * @param amountLend The amount of collateral tokens to lend
     * @param amountBorrow The amount of loan tokens to borrow (can be 0)
     * @param kintoWallet The address of the Kinto wallet to send borrowed assets to
     * @param bridgeData The data required for bridging borrowed assets
     * @return borrowed The amount of loan tokens borrowed
     */
    function lendAndBorrow(
        uint256 amountLend,
        uint256 amountBorrow,
        address kintoWallet,
        IBridger.BridgeData memory bridgeData
    ) public returns (uint256 borrowed) {
        // Get market params
        MarketParams memory marketParams = _getMarketParams();

        if (amountLend > 0) {
            // Approve Morpho to spend collateral tokens
            IERC20(COLLATERAL_TOKEN).forceApprove(MORPHO, amountLend);

            // Supply collateral to Morpho
            IMorpho(MORPHO).supplyCollateral(marketParams, amountLend, address(this), "");
        }

        // If amountBorrow > 0, borrow loan tokens
        if (amountBorrow > 0) {
            if (!IMorpho(MORPHO).isAuthorized(address(this), PRE_LIQUIDATION)) {
                IMorpho(MORPHO).setAuthorization(address(PRE_LIQUIDATION), true);
            }
            // Borrow loan tokens from Morpho
            (borrowed,) = IMorpho(MORPHO).borrow(marketParams, amountBorrow, 0, address(this), address(this));

            // Approve max allowance to save on gas for future transfers
            if (IERC20(LOAN_TOKEN).allowance(address(this), address(BRIDGER)) < borrowed) {
                IERC20(LOAN_TOKEN).forceApprove(address(BRIDGER), type(uint256).max);
            }

            IBridger(BRIDGER).depositERC20(
                LOAN_TOKEN, borrowed, kintoWallet, LOAN_TOKEN, borrowed, bytes(""), bridgeData
            );
        }

        return borrowed;
    }

    /**
     * @notice Repays a loan in the Morpho protocol without withdrawing collateral
     * @dev This is a simplified version of repayAndWithdraw with zero withdraw amount and empty bridge data
     * @param amountRepay The amount of loan tokens to repay
     */
    function repay(uint256 amountRepay) external {
        repayAndWithdraw(
            amountRepay,
            0,
            address(0),
            IBridger.BridgeData({ // empty “zero” BridgeData:
                vault: address(0),
                gasFee: 0,
                msgGasLimit: 0,
                connector: address(0),
                execPayload: bytes(""), // or new bytes(0)
                options: bytes("") // or new bytes(0)
            })
        );
    }

    /**
     * @notice Repays loan and optionally withdraws collateral
     * @dev Handles both repayment and withdrawal in a single transaction, with option to bridge withdrawn collateral
     * @param amountRepay The amount of loan tokens to repay (can be 0)
     * @param amountWithdraw The amount of collateral tokens to withdraw (can be 0)
     * @param kintoWallet The address of the Kinto wallet to send withdrawn collateral to
     * @param bridgeData The data required for bridging withdrawn collateral
     */
    function repayAndWithdraw(
        uint256 amountRepay,
        uint256 amountWithdraw,
        address kintoWallet,
        IBridger.BridgeData memory bridgeData
    ) public {
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

            // Approve max allowance to save on gas for future transfers
            if (IERC20(COLLATERAL_TOKEN).allowance(address(this), address(BRIDGER)) < amountWithdraw) {
                IERC20(COLLATERAL_TOKEN).forceApprove(address(BRIDGER), type(uint256).max);
            }

            IBridger(BRIDGER).depositERC20(
                COLLATERAL_TOKEN, amountWithdraw, kintoWallet, COLLATERAL_TOKEN, amountWithdraw, bytes(""), bridgeData
            );
        }
    }

    /**
     * @notice Supplies assets to Morpho protocol
     * @dev Supplies loan tokens (USDC.e) to the Morpho market
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
     * @notice Withdraws assets from Morpho protocol and bridges them to a Kinto wallet
     * @dev Withdraws loan tokens (USDC.e) from the Morpho market and sends them to a specified wallet through the bridge
     * @param amountWithdraw The amount of assets to withdraw
     * @param kintoWallet The address of the Kinto wallet to send withdrawn assets to
     * @param bridgeData The data required for bridging withdrawn assets
     */
    function withdraw(uint256 amountWithdraw, address kintoWallet, IBridger.BridgeData memory bridgeData) external {
        // Get market params
        MarketParams memory marketParams = _getMarketParams();

        // Withdraw from Morpho
        IMorpho(MORPHO).withdraw(marketParams, amountWithdraw, 0, address(this), address(this));

        // Approve max allowance to save on gas for future transfers
        if (IERC20(LOAN_TOKEN).allowance(address(this), address(BRIDGER)) < amountWithdraw) {
            IERC20(LOAN_TOKEN).forceApprove(address(BRIDGER), type(uint256).max);
        }

        IBridger(BRIDGER).depositERC20(
            LOAN_TOKEN, amountWithdraw, kintoWallet, LOAN_TOKEN, amountWithdraw, bytes(""), bridgeData
        );
    }
}

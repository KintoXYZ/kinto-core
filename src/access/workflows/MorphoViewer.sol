// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import {Initializable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Id, IMorpho, MarketParams, Position, Market} from "@kinto-core/interfaces/external/IMorpho.sol";
import {IPreLiquidationFactory} from "@kinto-core/interfaces/external/IMorphoPreLiquidationFactory.sol";
import {IPreLiquidation, PreLiquidationParams} from "@kinto-core/interfaces/external/IMorphoPreLiquidation.sol";

interface IOracle {
    function price() external view returns (uint256);
}

/// @title IIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Interface that Interest Rate Models (IRMs) used by Morpho must implement.
interface IIrm {
    /// @notice Returns the borrow rate per second (scaled by WAD) of the market `marketParams`.
    /// @dev Assumes that `market` corresponds to `marketParams`.
    function borrowRate(MarketParams memory marketParams, Market memory market) external returns (uint256);

    /// @notice Returns the borrow rate per second (scaled by WAD) of the market `marketParams` without modifying any
    /// storage.
    /// @dev Assumes that `market` corresponds to `marketParams`.
    function borrowRateView(MarketParams memory marketParams, Market memory market) external view returns (uint256);
}

/**
 * @title MorphoViewer
 * @notice View contract for interacting with Morpho protocol data
 * @dev Provides read-only functions to view market and position data from Morpho markets on Arbitrum
 *      Upgradeable using the UUPS pattern and owned by a single owner
 */
contract MorphoViewer is Initializable, UUPSUpgradeable, OwnableUpgradeable {
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

    /// @notice The length of the data used to compute the id of a market.
    /// @dev The length is 5 * 32 because `MarketParams` has 5 variables of 32 bytes each.
    uint256 internal constant MARKET_PARAMS_BYTES_LENGTH = 5 * 32;

    /// @notice WAD precision (10^18)
    uint256 internal constant WAD = 1e18;

    /// @dev Initializes the contract in a disabled state to prevent its use without proxy.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract setting up the owner and making it ready for upgrades
     * @dev This function can only be called once due to the initializer modifier
     */
    function initialize() external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        _transferOwnership(msg.sender);
    }

    /**
     * @dev Authorizes upgrade to a new implementation
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        (newImplementation); // This line prevents unused variable warning.
    }

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

    /* ============ External View Functions ============ */

    /**
     * @notice Get market information including total supply, total borrow, and interest rates
     * @dev Accrues interest before returning the values to ensure data is up-to-date
     * @return totalSupply Total supply assets in the market
     * @return totalBorrow Total borrow assets in the market
     * @return borrowRatePerSecond Current borrow rate per second in the market (scaled by 10^18)
     * @return supplyRatePerSecond Current supply rate per second in the market (scaled by 10^18)
     */
    function marketInfo()
        external
        returns (uint256 totalSupply, uint256 totalBorrow, uint256 borrowRatePerSecond, uint256 supplyRatePerSecond)
    {
        MarketParams memory marketParams = _getMarketParams();
        Id marketId = id(marketParams);

        // Accrue interest to ensure up-to-date values
        IMorpho(MORPHO).accrueInterest(marketParams);

        // Get market data
        Market memory market = IMorpho(MORPHO).market(marketId);
        totalSupply = market.totalSupplyAssets;
        totalBorrow = market.totalBorrowAssets;

        // Get borrow rate per second directly from IRM
        borrowRatePerSecond = IIrm(IRM).borrowRateView(marketParams, market);

        // Supply rate is derived from borrow rate and the utilization rate
        // supplyRatePerSecond = borrowRatePerSecond * utilization * (1 - fee)
        uint256 utilization = totalBorrow == 0 ? 0 : (totalBorrow * WAD) / totalSupply;
        uint256 fee = market.fee;
        supplyRatePerSecond = (borrowRatePerSecond * utilization * (WAD - fee)) / (WAD * WAD);

        return (totalSupply, totalBorrow, borrowRatePerSecond, supplyRatePerSecond);
    }

    /**
     * @notice Get a user's position details in the market
     * @dev Accrues interest before returning the values to ensure data is up-to-date
     * @param user Address of the user to check
     * @return supplyAssets Amount of assets supplied by the user
     * @return borrowAssets Amount of assets borrowed by the user
     * @return collateral Amount of collateral provided by the user
     */
    function position(address user) external returns (uint256 supplyAssets, uint256 borrowAssets, uint256 collateral) {
        MarketParams memory marketParams = _getMarketParams();
        Id marketId = id(marketParams);

        // Accrue interest to ensure up-to-date values
        IMorpho(MORPHO).accrueInterest(marketParams);

        // Get position data
        Position memory pos = IMorpho(MORPHO).position(marketId, user);
        Market memory market = IMorpho(MORPHO).market(marketId);

        // Calculate assets from shares
        supplyAssets =
            pos.supplyShares == 0 ? 0 : (pos.supplyShares * market.totalSupplyAssets) / market.totalSupplyShares;
        borrowAssets = pos.borrowShares == 0
            ? 0
            : (uint256(pos.borrowShares) * market.totalBorrowAssets) / market.totalBorrowShares;
        collateral = pos.collateral;

        return (supplyAssets, borrowAssets, collateral);
    }

    /**
     * @notice Calculate Loan-to-Value ratio and health factor for a user, optionally with hypothetical lending and borrowing amounts
     * @dev When lendAmount and borrowAmount are 0, returns the current LTV and health factor
     * @param user Address of the user to check
     * @param lendAmount Additional collateral amount to simulate lending (0 for current position)
     * @param borrowAmount Additional borrow amount to simulate borrowing (0 for current position)
     * @return ltv The Loan-to-Value ratio after the operation (scaled by 10^18)
     * @return healthFactor The health factor of the position (scaled by 10^18). Above 1.0 is healthy.
     */
    function calculateLTV(address user, uint256 lendAmount, uint256 borrowAmount)
        external
        returns (uint256 ltv, uint256 healthFactor)
    {
        MarketParams memory marketParams = _getMarketParams();
        Id marketId = id(marketParams);

        // Accrue interest to ensure up-to-date values
        IMorpho(MORPHO).accrueInterest(marketParams);

        // Get position data
        Position memory pos = IMorpho(MORPHO).position(marketId, user);
        Market memory market = IMorpho(MORPHO).market(marketId);

        // Calculate current assets from shares
        uint256 currentBorrowAssets = pos.borrowShares == 0
            ? 0
            : (uint256(pos.borrowShares) * market.totalBorrowAssets) / market.totalBorrowShares;
        uint256 currentCollateral = pos.collateral;

        // Add hypothetical amounts
        uint256 totalBorrowAssets = currentBorrowAssets + borrowAmount;
        uint256 totalCollateral = currentCollateral + lendAmount;

        // Get oracle price
        uint256 price = IOracle(ORACLE).price();

        // Calculate collateral value in loan token units
        // Price is in USD per collateral token (scaled by 1e18)
        // USDC.e has 6 decimals, K token has 18 decimals
        // Need to adjust for decimals: collateral (1e18) * price (1e24) / (1e18 * 1e18) = value in USDC (1e6)
        uint256 collateralValueInLoanTokens = totalCollateral == 0 ? 0 : (totalCollateral * price) / (WAD * WAD);

        // Calculate LTV
        ltv = collateralValueInLoanTokens == 0 ? 0 : (totalBorrowAssets * WAD) / collateralValueInLoanTokens;

        // Calculate health factor
        // Health factor = (collateralValueInLoanTokens * LLTV) / (totalBorrowAssets * WAD)
        // A health factor > 1.0 means the position is healthy
        // A health factor < 1.0 means the position can be liquidated
        healthFactor = totalBorrowAssets == 0
            ? type(uint256).max // No debt means infinite health factor
            : (collateralValueInLoanTokens * LLTV) / (totalBorrowAssets);

        return (ltv, healthFactor);
    }
}

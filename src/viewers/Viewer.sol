// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IAavePool, IPoolAddressesProvider} from "@kinto-core/interfaces/external/IAavePool.sol";
import {IAccessRegistry} from "@kinto-core/interfaces/IAccessRegistry.sol";

/**
 * @title Viewer Smart Contract
 * @dev This contract serves as a view-only interface that allows querying token balances for a specified address.
 *      It is upgradeable using the UUPS pattern and is owned by a single owner.
 */
contract Viewer is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    /**
     * @notice Structure containing market and user data for a specific asset
     * @dev All rates are in WAD (1e18 = 100%) and amounts in underlying token decimals
     */
    struct AssetData {
        // Aave protocol data
        uint256 aaveSupplyAPY; // Current Aave supply APY for the asset (1e18 = 100%)
        uint256 aaveSupplyCapacity; // Maximum amount that can be supplied to the Aave market
        uint256 aaveSupplyAmount; // Amount currently supplied to Aave by the user
        uint256 aaveBorrowAPY; // Current Aave variable borrow APY for the asset (1e18 = 100%)
        uint256 aaveBorrowCapacity; // Maximum amount that can be borrowed from the Aave market
        uint256 aaveBorrowAmount; // Amount currently borrowed from Aave by the user
        // Wallet balances
        uint256 tokenBalance; // Balance of the underlying token in the access point
        uint256 aTokenBalance; // Balance of the Aave interest bearing token in the access point
    }

    /**
     * @notice Structure containing account-level data and per-asset data
     * @dev Account metrics are in base currency units
     */
    struct AccountData {
        uint256 aaveTotalCollateralBase; // Total collateral of the user in Aave
        uint256 aaveTotalDebtBase; // Total debt of the user in Aave
        uint256 aaveAvailableBorrowsBase; // Borrowing power left in Aave
        uint256 aaveCurrentLiquidationThreshold; // Aave liquidation threshold (1e4 = 100%)
        uint256 aaveLtv; // Aave loan to value (1e4 = 100%)
        uint256 aaveHealthFactor; // Aave health factor (1e18 = 1)
        AssetData[] assets; // Array of per-asset data
    }

    IPoolAddressesProvider public immutable poolAddressProvider;
    IAccessRegistry public immutable accessRegistry;

    /// @dev Initializes the contract in a disabled state to prevent its use without proxy.
    constructor(address poolAddressProvider_, address accessRegistry_) {
        _disableInitializers();

        poolAddressProvider = IPoolAddressesProvider(poolAddressProvider_);
        accessRegistry = IAccessRegistry(accessRegistry_);
    }

    /**
     * @dev Initializes the contract setting up the owner and making it ready for upgrades.
     *      This function can only be called once, due to the `initializer` modifier.
     */
    function initialize() external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        _transferOwnership(msg.sender);
    }

    /**
     * @dev Overrides the UUPSUpgradeable's _authorizeUpgrade to add security by restricting
     *      upgrade authorization to only the owner of the contract.
     * @param newImplementation Address of the new contract implementation to which upgrade will happen.
     */
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        // Optional: Add custom logic for upgrade authorization or validation of new implementation
        (newImplementation); // This line prevents unused variable warning.
    }

    /**
     * @notice Retrieves the ERC20 token balances for a specific target address.
     * @dev This view function allows fetching balances for multiple tokens in a single call,
     *         which can save considerable gas over multiple calls.
     * @param tokens An array of token addresses to query balances for.
     * @param target The address whose balances will be queried.
     * @return balances An array of balances corresponding to the array of tokens provided.
     */
    function getBalances(address[] memory tokens, address target) external view returns (uint256[] memory balances) {
        balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = IERC20(tokens[i]).balanceOf(target);
        }
    }

    /**
     * @notice Retrieves comprehensive user and market data for multiple assets from Aave V3
     * @dev All rates are normalized to WAD (1e18 = 100%)
     * @param assets Array of token addresses to fetch data for
     * @param kintoSigner Address of the user wallet to check balances for
     * @return data AccountData struct containing both account-level metrics and per-asset data
     */
    function getAccountData(address[] calldata assets, address kintoSigner)
        external
        view
        returns (AccountData memory data)
    {
        address accessPoint = address(accessRegistry.getAccessPoint(kintoSigner));
        IAavePool pool = IAavePool(poolAddressProvider.getPool());

        // Initialize assets array in memory
        data.assets = new AssetData[](assets.length);

        {
            // Get user account data
            (
                uint256 totalCollateralBase,
                uint256 totalDebtBase,
                uint256 availableBorrowsBase,
                uint256 currentLiquidationThreshold,
                uint256 ltv,
                uint256 healthFactor
            ) = pool.getUserAccountData(accessPoint);

            // Set account data
            data.aaveTotalCollateralBase = totalCollateralBase;
            data.aaveTotalDebtBase = totalDebtBase;
            data.aaveAvailableBorrowsBase = availableBorrowsBase;
            data.aaveCurrentLiquidationThreshold = currentLiquidationThreshold;
            data.aaveLtv = ltv;
            data.aaveHealthFactor = healthFactor;
        }

        // Get per-asset data
        for (uint256 i = 0; i < assets.length; i++) {
            IAavePool.ReserveDataLegacy memory reserveData = pool.getReserveData(assets[i]);
            IAavePool.ReserveConfigurationMap memory config = pool.getConfiguration(assets[i]);

            uint256 supplyBalance = IERC20(reserveData.aTokenAddress).balanceOf(accessPoint);
            uint256 borrowBalance = IERC20(reserveData.variableDebtTokenAddress).balanceOf(accessPoint);
            uint256 tokenBalance = IERC20(assets[i]).balanceOf(accessPoint);
            uint256 aTokenBalance = IERC20(reserveData.aTokenAddress).balanceOf(accessPoint);

            data.assets[i] = AssetData({
                aaveSupplyAPY: _rayToAPY(reserveData.currentLiquidityRate),
                aaveSupplyCapacity: _getSupplyCap(config),
                aaveSupplyAmount: supplyBalance,
                aaveBorrowAPY: _rayToAPY(reserveData.currentVariableBorrowRate),
                aaveBorrowCapacity: _getBorrowCap(config),
                aaveBorrowAmount: borrowBalance,
                tokenBalance: tokenBalance,
                aTokenBalance: aTokenBalance
            });
        }
    }

    /**
     * @notice Converts Aave's ray rate (1e27) to APY in WAD format (1e18 = 100%)
     * @dev Simple conversion from ray to WAD as rates are already annualized
     * @param rayRate Interest rate in ray format (1e27)
     * @return APY in WAD format where 1e18 = 100%
     */
    function _rayToAPY(uint256 rayRate) internal pure returns (uint256) {
        return rayRate / 1e9; // Convert from ray (1e27) to WAD (1e18)
    }

    /**
     * @notice Extracts supply cap from Aave configuration data
     * @dev Reads bits 116-151 from the configuration data
     * @param config Reserve configuration map from Aave
     * @return Supply cap in whole tokens (0 means no cap)
     */
    function _getSupplyCap(IAavePool.ReserveConfigurationMap memory config) internal pure returns (uint256) {
        // Get bits 116-151 (36 bits)
        return uint256((config.data >> 116) & ~uint256(0) >> (256 - 36));
    }

    /**
     * @notice Extracts borrow cap from Aave configuration data
     * @dev Reads bits 80-115 from the configuration data
     * @param config Reserve configuration map from Aave
     * @return Borrow cap in whole tokens (0 means no cap)
     */
    function _getBorrowCap(IAavePool.ReserveConfigurationMap memory config) internal pure returns (uint256) {
        // Get bits 80-115 (36 bits)
        return uint256((config.data >> 80) & ~uint256(0) >> (256 - 36));
    }
}

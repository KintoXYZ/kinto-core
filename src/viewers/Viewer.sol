// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IAavePool, ILendingPoolAddressesProvider} from "@kinto-core/interfaces/external/IAavePool.sol";

/**
 * @title Viewer Smart Contract
 * @dev This contract serves as a view-only interface that allows querying token balances for a specified address.
 *      It is upgradeable using the UUPS pattern and is owned by a single owner.
 */
contract Viewer is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    /**
     * @notice Structure containing user and market data for a specific asset
     * @dev All rates are in WAD (1e18 = 100%) and amounts in underlying token decimals
     */
    struct AaveUserData {
        uint256 supplyAPY; // Current supply APY for the asset (1e18 = 100%)
        uint256 supplyCapacity; // Maximum amount that can be supplied to the market
        uint256 userSupplyAmount; // Amount currently supplied by the user
        uint256 borrowAPY; // Current variable borrow APY for the asset (1e18 = 100%)
        uint256 borrowCapacity; // Maximum amount that can be borrowed from the market
        uint256 userBorrowAmount; // Amount currently borrowed by the user
    }

    ILendingPoolAddressesProvider public immutable poolAddressProvider;

    /// @dev Initializes the contract in a disabled state to prevent its use without proxy.
    constructor(address poolAddressProvider_) {
        _disableInitializers();

        poolAddressProvider = ILendingPoolAddressesProvider(poolAddressProvider_);
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
     * @notice Retrieves user and market data for multiple assets from Aave V3
     * @dev All rates are normalized to WAD (1e18 = 100%)
     * @param assets Array of token addresses to fetch data for
     * @param kintoWallet Address of the user wallet to check balances for
     * @return metrics Array of AaveUserData structs containing user and market data for each asset
     */
    function getAaveUserData(address[] calldata assets, address kintoWallet)
        external
        view
        returns (AaveUserData[] memory metrics)
    {
        IAavePool pool = IAavePool(poolAddressProvider.getLendingPool());
        metrics = new AaveUserData[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            IAavePool.ReserveDataLegacy memory reserveData = pool.getReserveData(assets[i]);
            IAavePool.ReserveConfigurationMap memory config = pool.getConfiguration(assets[i]);

            uint256 supplyBalance = IERC20(reserveData.aTokenAddress).balanceOf(kintoWallet);
            uint256 borrowBalance = IERC20(reserveData.variableDebtTokenAddress).balanceOf(kintoWallet);

            metrics[i] = AaveUserData({
                supplyAPY: _rayToAPY(reserveData.currentLiquidityRate),
                supplyCapacity: _getSupplyCap(config),
                userSupplyAmount: supplyBalance,
                borrowAPY: _rayToAPY(reserveData.currentVariableBorrowRate),
                borrowCapacity: _getBorrowCap(config),
                userBorrowAmount: borrowBalance
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

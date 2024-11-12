// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import {IWETH} from "@kinto-core/interfaces/IWETH.sol";

import {IAavePool, IPoolAddressesProvider} from "@kinto-core/interfaces/external/IAavePool.sol";

/**
 * @title AaveWithdrawWorkflow
 * @notice Allows withdrawing funds from Aave markets
 */
contract AaveWithdrawWorkflow {
    using SafeERC20 for IERC20;
    using Address for address;

    /* ============ Immutable Storage ============ */

    /// @notice Address of the PoolAddressesProvider contract
    IPoolAddressesProvider public immutable poolAddressProvider;

    /* ============ Constructor ============ */

    /**
     * @notice Initializes the contract with Aave's pool address provider
     * @param poolAddressProvider_ The address of Aave's pool address provider
     */
    constructor(address poolAddressProvider_) {
        poolAddressProvider = IPoolAddressesProvider(poolAddressProvider_);
    }

    /* ============ External Functions ============ */

    /**
     * @notice Withdraws assets from Aave
     * @param asset The address of the asset to withdraw
     * @param amount The amount to withdraw (use type(uint256).max for max available)
     * @param receiver The address that will receive the withdrawn assets
     */
    function withdraw(address asset, uint256 amount, address receiver) external {
        address pool = poolAddressProvider.getPool();

        // If amount is max uint256, withdraw all available
        if (amount == type(uint256).max) {
            amount = IERC20(IAavePool(pool).getReserveData(asset).aTokenAddress).balanceOf(address(this));
        }

        // Withdraw from Aave
        IAavePool(pool).withdraw(asset, amount, receiver);
    }
}

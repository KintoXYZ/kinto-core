// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import {IWETH} from "@kinto-core/interfaces/IWETH.sol";

import {IAavePool, IPoolAddressesProvider} from "@kinto-core/interfaces/external/IAavePool.sol";

/**
 * @title AaveRepayWorkflow
 * @notice Allows repaying borrowed assets to Aave markets
 */
contract AaveRepayWorkflow {
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
     * @notice Repays a borrowed asset to Aave
     * @param asset The address of the borrowed asset to repay
     * @param amount The amount to repay (use type(uint256).max for max debt)
     * @param onBehalfOf The address of the user who will get their debt reduced
     * @return amountRepaid The actual amount repaid
     */
    function repay(address asset, uint256 amount, address onBehalfOf) external returns (uint256) {
        address pool = poolAddressProvider.getPool();

        // If amount is max uint256, get the debt for this specific asset
        if (amount == type(uint256).max) {
            amount = IERC20(IAavePool(pool).getReserveData(asset).variableDebtTokenAddress).balanceOf(onBehalfOf);
        }

        // Approve max allowance to save on gas for future transfers
        if (IERC20(asset).allowance(address(this), pool) < amount) {
            IERC20(asset).forceApprove(pool, type(uint256).max);
        }

        // Repay to Aave
        return IAavePool(pool).repay(
            asset,
            amount,
            2, // RATE_MODE: 2 for variable rate
            onBehalfOf
        );
    }
}

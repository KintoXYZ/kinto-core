// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import {IWETH} from "@kinto-core/interfaces/IWETH.sol";

import {IAavePool, IPoolAddressesProvider} from "@kinto-core/interfaces/external/IAavePool.sol";

/**
 * @title AaveLendWorkflow
 * @notice It allows to deposit funds into Aave markets.
 */
contract AaveLendWorkflow {
    using SafeERC20 for IERC20;
    using Address for address;

    /// @notice Address of the PoolAddressesProvider contract.
    IPoolAddressesProvider public immutable poolAddressProvider;

    constructor(address poolAddressProvider_) {
        poolAddressProvider = IPoolAddressesProvider(poolAddressProvider_);
    }

    function lend(address assetIn, uint256 amountIn) external payable {
        if (amountIn == 0) {
            amountIn = IERC20(assetIn).balanceOf(address(this));
        }

        address pool = poolAddressProvider.getPool();

        // Approve max allowance to save on gas for future transfers
        if (IERC20(assetIn).allowance(address(this), address(pool)) < amountIn) {
            IERC20(assetIn).forceApprove(address(pool), type(uint256).max);
        }

        IAavePool(pool).supply(assetIn, amountIn, address(this), 0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import {IWETH} from "@kinto-core/interfaces/IWETH.sol";
import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";

import {IAavePool, IPoolAddressesProvider} from "@kinto-core/interfaces/external/IAavePool.sol";

/**
 * @title AaveBorrowWorkflow
 * @notice Allows borrowing assets from Aave markets
 */
contract AaveBorrowWorkflow {
    using SafeERC20 for IERC20;
    using Address for address;

    /* ============ Immutable Storage ============ */

    /// @notice Address of the PoolAddressesProvider contract
    IPoolAddressesProvider public immutable poolAddressProvider;
    /// @notice Address of the Bridger contract
    IBridger public immutable bridger;

    /* ============ Constructor ============ */

    /**
     * @notice Initializes the contract with Aave's pool address provider
     * @param poolAddressProvider_ The address of Aave's pool address provider
     */
    constructor(address poolAddressProvider_, address bridger_) {
        poolAddressProvider = IPoolAddressesProvider(poolAddressProvider_);
        bridger = IBridger(bridger_);
    }

    /* ============ External Functions ============ */

    /**
     * @notice Borrows an asset from Aave
     * @param asset The address of the asset to borrow
     * @param amount The amount to borrow
     */
    function borrow(address asset, uint256 amount) public {
        IAavePool(poolAddressProvider.getPool()).borrow(
            asset,
            amount,
            2, // RATE_MODE: 2 for variable rate
            0, // referral code (0 for none)
            address(this)
        );
    }

    function borrowAndBridge(
        address asset,
        uint256 amount,
        address kintoWallet,
        IBridger.BridgeData calldata bridgeData
    ) external payable returns (uint256 amountOut) {
        borrow(asset, amount);

        // Approve max allowance to save on gas for future transfers
        if (IERC20(asset).allowance(address(this), address(bridger)) < amount) {
            IERC20(asset).forceApprove(address(bridger), type(uint256).max);
        }

        return bridger.depositERC20(asset, amount, kintoWallet, asset, amount, bytes(""), bridgeData);
    }
}

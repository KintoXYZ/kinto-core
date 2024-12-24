// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import {IWETH} from "@kinto-core/interfaces/IWETH.sol";
import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";

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
    /// @notice Address of the Bridger contract
    IBridger public immutable bridger;
    /// @notice Address of the Safe contract
    address public immutable safe;
    /// @notice Fee charged upon withdrawal. 10bps.
    uint256 public constant FEE = 1e15;

    /* ============ Constructor ============ */

    /**
     * @notice Initializes the contract with Aave's pool address provider
     * @param poolAddressProvider_ The address of Aave's pool address provider
     */
    constructor(address poolAddressProvider_, address bridger_, address safe_) {
        poolAddressProvider = IPoolAddressesProvider(poolAddressProvider_);
        bridger = IBridger(bridger_);
        safe = safe_;
    }

    /* ============ External Functions ============ */

    /**
     * @notice Withdraws assets from Aave
     * @param asset The address of the asset to withdraw
     * @param amount The amount to withdraw (use type(uint256).max for max available)
     */
    function withdraw(address asset, uint256 amount) public returns (uint256) {
        address pool = poolAddressProvider.getPool();

        // If amount is max uint256, withdraw all available
        if (amount == type(uint256).max) {
            amount = IERC20(IAavePool(pool).getReserveData(asset).aTokenAddress).balanceOf(address(this));
        }

        // Withdraw from Aave
        IAavePool(pool).withdraw(asset, amount, address(this));
        // Send the fee to the Safe
        uint256 fee = amount * FEE / 1e18;
        IERC20(asset).transfer(safe, fee);
        return amount - fee;
    }

    function withdrawAndBridge(
        address asset,
        uint256 amount,
        address kintoWallet,
        IBridger.BridgeData calldata bridgeData
    ) external payable returns (uint256 amountOut) {
        amount = withdraw(asset, amount);

        // Approve max allowance to save on gas for future transfers
        if (IERC20(asset).allowance(address(this), address(bridger)) < amount) {
            IERC20(asset).forceApprove(address(bridger), type(uint256).max);
        }

        return bridger.depositERC20(asset, amount, kintoWallet, asset, amount, bytes(""), bridgeData);
    }
}

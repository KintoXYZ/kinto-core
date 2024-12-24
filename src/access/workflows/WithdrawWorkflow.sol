// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH} from "@kinto-core/interfaces/IWETH.sol";

import {IAccessPoint} from "../../interfaces/IAccessPoint.sol";

/**
 * @title WithdrawWorkflow
 * @notice Workflow contract for withdrawing assets from an access point to its owner
 * @dev Supports withdrawing ERC20 tokens and native ETH. When withdrawing native ETH,
 *      automatically unwraps WETH if native balance is insufficient.
 */
contract WithdrawWorkflow {
    using SafeERC20 for IERC20;

    /* ============ Errors ============ */

    /// @notice Thrown when native ETH withdrawal fails
    error NativeWithdrawalFailed();

    /* ============ Constants & Immutables ============ */

    /// @notice The address of WETH token contract
    address public immutable WETH;

    /* ============ Constructor ============ */

    /**
     * @notice Initializes the workflow with WETH address
     * @param weth Address of the WETH contract
     */
    constructor(address weth) {
        WETH = weth;
    }

    /* ============ External Functions ============ */

    /**
     * @notice Withdraws ERC20 tokens to the access point owner
     * @param asset The ERC20 token to withdraw
     * @param amount The amount to withdraw (use type(uint256).max for entire balance)
     */
    function withdrawERC20(IERC20 asset, uint256 amount) external {
        // If amount is max uint256, set it to the entire balance
        if (amount == type(uint256).max) {
            amount = asset.balanceOf(address(this));
        }

        address owner = _getOwner();
        asset.safeTransfer({to: owner, value: amount});
    }

    /**
     * @notice Withdraws native ETH to the access point owner
     * @dev First attempts to use native ETH balance, then unwraps WETH if needed
     * @param amount The amount of ETH to withdraw
     */
    function withdrawNative(uint256 amount) external {
        address owner = _getOwner();

        // If amount is max uint256, set it to the entire balance
        if (amount == type(uint256).max) {
            IWETH(WETH).withdraw(IERC20(WETH).balanceOf(address(this)));
            amount = address(this).balance;
        }

        if (address(this).balance < amount) {
            if (IERC20(WETH).balanceOf(address(this)) >= amount) {
                IWETH(WETH).withdraw(amount);
            } else {
                revert NativeWithdrawalFailed();
            }
        }
        (bool sent,) = owner.call{value: amount}("");
        if (!sent) {
            revert NativeWithdrawalFailed();
        }
    }

    /* ============ Internal Functions ============ */

    /**
     * @dev Gets the owner address of this access point
     * @return The owner address
     */
    function _getOwner() internal view returns (address) {
        return IAccessPoint(address(this)).owner();
    }
}

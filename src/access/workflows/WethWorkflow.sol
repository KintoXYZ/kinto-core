// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import {IWETH} from "@kinto-core/interfaces/IWETH.sol";

/**
 * @title WethWorkflow
 * @notice It allows to deposit and withdraw of ETH in exchange for WETH.
 */
contract WethWorkflow {
    using SafeERC20 for IERC20;
    using Address for address;

    /// @notice Address of the WETH contract.
    IWETH public immutable weth;

    /// @dev Constructor sets the WETH contract address.
    /// @param _weth Address of the WETH contract to be used.
    constructor(address _weth) {
        weth = IWETH(_weth);
    }

    /**
     * @notice Deposits ETH and mints WETH.
     * @param amount The amount of ETH in wei to be wrapped.
     */
    function deposit(uint256 amount) external payable {
        // The deposit is called on the WETH contract using call value to send Ether.
        // slither-disable-next-line arbitrary-send-eth
        weth.deposit{value: amount}();
    }

    /**
     * @notice Withdraws ETH by burning wrapped WETH.
     * @param amount The amount of WETH in wei to be unwrapped.
     */
    function withdraw(uint256 amount) external {
        // Withdraw the specified amount of Ether from the WETH contract.
        weth.withdraw(amount);
    }
}

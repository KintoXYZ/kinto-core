// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import {IWETH9 as IWETH} from "@token-bridge-contracts/contracts/tokenbridge/libraries/IWETH9.sol";

import {IAccessPoint} from "../../interfaces/IAccessPoint.sol";

contract WethWorkflow {
    using SafeERC20 for IERC20;
    using Address for address;

    IWETH public immutable weth;

    constructor(address _weth) {
        weth = IWETH(_weth);
    }

    /// @notice Deposit ether to get wrapped ether
    function deposit(uint256 amount) external {
        weth.deposit{value: amount}();
    }

    /// @notice Withdraw wrapped ether to get ether
    function withdraw(uint256 amount) external {
        weth.withdraw(amount);
    }
}

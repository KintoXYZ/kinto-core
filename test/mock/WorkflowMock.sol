// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import {IWETH} from "@kinto-core/interfaces/IWETH.sol";

contract WorkflowMock {
    using SafeERC20 for IERC20;
    using Address for address;

    constructor() {}

    function answer() external pure returns (uint256) {
        return 42;
    }
}

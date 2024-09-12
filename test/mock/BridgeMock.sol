// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IBridge} from "@kinto-core/interfaces/bridger/IBridge.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";

contract BridgeMock is IBridge {
    using SafeERC20 for IERC20;

    address internal token;

    constructor(address _token) {
        token = _token;
    }

    function bridge(address, uint256 amount, uint256, address, bytes calldata, bytes calldata) external payable {
        // pull that tokens in, as real vault does
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    function receiveInbound(uint32, bytes memory) external payable {}

    function retry(address, bytes32) external {}
}

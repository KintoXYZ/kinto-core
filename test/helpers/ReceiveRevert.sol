// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

contract ReceiveRevert {
    error ReceiveRevert(address sender, uint256 amount);

    receive() external payable {
        revert ReceiveRevert(msg.sender, msg.value);
    }
}

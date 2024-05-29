// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

contract ReceiveRevert {
    error Reject(address sender, uint256 amount);

    receive() external payable {
        revert Reject(msg.sender, msg.value);
    }
}

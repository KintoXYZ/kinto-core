// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

contract Receiver {
    event Received(address, uint);
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}

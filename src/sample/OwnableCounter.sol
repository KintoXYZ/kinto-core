// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Counter.sol";
import "@oz/contracts/access/Ownable.sol";

contract OwnableCounter is Counter, Ownable {
    constructor() Ownable(msg.sender) {}

    function increment() public override onlyOwner {
        count += 1;
    }
}

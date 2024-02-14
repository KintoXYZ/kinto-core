// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Counter.sol";
import "@openzeppelins/contracts/access/Ownable.sol";

contract OwnableCounter is Counter, Ownable {
    constructor() Ownable(msg.sender) {}

    function increment() public override onlyOwner {
        count += 1;
    }
}

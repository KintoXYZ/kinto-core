// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Counter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract OwnableCounter is Counter, Ownable {
    constructor() Ownable() {}

    function increment() public override onlyOwner {
        count += 1;
    }
}

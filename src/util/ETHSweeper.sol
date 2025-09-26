// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract ETHSweeper {
    address public constant SAFE = 0x2E7111Ef34D39b36EC84C656b947CA746e495Ff6;

    function sweep() public {
        (bool sent,) = SAFE.call{value: address(this).balance}("");
        require(sent, "Failed to sweep");
    }
}

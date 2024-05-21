// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice An implementation of Wrapped Ether.
contract WETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    /// @dev mint tokens for sender based on amount of ether sent.
    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    /// @dev withdraw ether based on requested amount and user balance.
    function withdraw(uint256 _amount) external {
        require(balanceOf(msg.sender) >= _amount, "insufficient balance.");
        _burn(msg.sender, _amount);
        payable(msg.sender).transfer(_amount);
    }
}

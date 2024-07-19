// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract ERC20Multisender {
    error TransferFailed();

    function multisendToken(address token, address[] calldata recipients, uint256[] calldata amounts) external {
        IERC20 erc20Token = IERC20(token);
        uint256 length = recipients.length;

        for (uint256 i; i < length;) {
            if (!erc20Token.transferFrom(msg.sender, recipients[i], amounts[i])) {
                revert TransferFailed();
            }
            unchecked {
                ++i;
            }
        }
    }
}

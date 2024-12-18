// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { StakeManager } from "@aa/core/StakeManager.sol";

interface IEntryPoint {
    function walletFactory() external view returns (address);
    function setWalletFactory(address _walletFactory) external;
}

contract EntryPointMock is StakeManager, IEntryPoint {
    address public walletFactory;

    function setWalletFactory(address _walletFactory) external {
        require(walletFactory == address(0), "AA36 wallet factory already set");
        walletFactory = _walletFactory;
    }

    function decodeContext(bytes calldata context) external pure returns (address,address,uint256,uint256) {
        (address account, address walletAccount, uint256 maxFeePerGas, uint256 maxPriorityFeePerGas) = 
            abi.decode(context, (address, address, uint256, uint256));
        return (account, walletAccount, maxFeePerGas, maxPriorityFeePerGas);
    }
}

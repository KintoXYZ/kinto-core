// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";

import {IBridge} from "@kinto-core/interfaces/bridger/IBridge.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";
import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";

contract CrossChainSwapWorkflow {
    using SafeERC20 for IERC20;
    /// @notice The address of the Bridger contract

    IBridger public immutable bridger;

    constructor(IBridger bridger_) {
        bridger = bridger_;
    }

    function swapAndBridge(
        address inputAsset,
        uint256 amount,
        address kintoWallet,
        address finalAsset,
        uint256 minReceive,
        bytes calldata swapCallData,
        IBridger.BridgeData calldata bridgeData
    ) external payable returns (uint256 amountOut) {
        if (amount == 0) {
            amount = IERC20(inputAsset).balanceOf(address(this));
        }

        // Approve max allowance to save on gas for future transfers
        if (IERC20(inputAsset).allowance(address(this), address(bridger)) < amount) {
            IERC20(inputAsset).forceApprove(address(bridger), type(uint256).max);
        }

        return bridger.depositERC20(inputAsset, amount, kintoWallet, finalAsset, minReceive, swapCallData, bridgeData);
    }
}

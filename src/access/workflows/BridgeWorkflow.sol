// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBridge} from "@kinto-core/interfaces/bridger/IBridge.sol";
import {IAccessPoint} from "@kinto-core/interfaces/IAccessPoint.sol";
import {IBridger} from "@kinto-core/interfaces/bridger/IBridger.sol";

contract BridgeWorkflow {
    using SafeERC20 for IERC20;

    /**
     * @notice Emitted when a bridge operation is made.
     * @param kintoWallet The address of the Kinto kintoWallet on L2.
     * @param inputAsset The address of the input inputAsset.
     * @param amount The amount of the input inputAsset.
     */
    event Bridged(address indexed kintoWallet, address indexed inputAsset, uint256 amount);

    IBridger public immutable bridger;

    constructor(IBridger bridger_) {
        bridger = bridger_;
    }

    function bridge(address inputAsset, uint256 amount, address kintoWallet, IBridger.BridgeData calldata bridgeData)
        external
        payable
        returns (uint256 amountOut)
    {
        if (bridger.bridgeVaults(bridgeData.vault) == false) revert IBridger.InvalidVault(bridgeData.vault);
        if (amount == 0) {
            amount = IERC20(inputAsset).balanceOf(address(this));
        }

        // Approve max allowance to save on gas for future transfers
        if (IERC20(inputAsset).allowance(address(this), address(bridger)) < amount) {
            IERC20(inputAsset).forceApprove(address(bridger), type(uint256).max);
        }

        // Bridge the amount to Kinto
        emit Bridged(kintoWallet, inputAsset, amount);
        return bridger.depositERC20(inputAsset, amount, kintoWallet, inputAsset, amount, bytes(""), bridgeData);
    }
}

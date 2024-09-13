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
     * @param wallet The address of the Kinto wallet on L2.
     * @param asset The address of the input asset.
     * @param amount The amount of the input asset.
     */
    event Bridged(address indexed wallet, address indexed asset, uint256 amount);

    IBridger public immutable bridger;

    constructor(IBridger bridger_) {
        bridger = bridger_;
    }

    function bridge(address asset, uint256 amount, address wallet, IBridger.BridgeData calldata bridgeData)
        external
        payable
    {
        if (bridger.bridgeVaults(bridgeData.vault) == false) revert IBridger.InvalidVault(bridgeData.vault);
        if (amount == 0) {
            amount = IERC20(asset).balanceOf(address(this));
        }

        // Approve max allowance to save on gas for future transfers
        if (IERC20(asset).allowance(address(this), bridgeData.vault) < amount) {
            IERC20(asset).forceApprove(bridgeData.vault, type(uint256).max);
        }

        // Bridge the amount to Kinto
        // slither-disable-next-line arbitrary-send-eth
        IBridge(bridgeData.vault).bridge{value: bridgeData.gasFee}(
            wallet, amount, bridgeData.msgGasLimit, bridgeData.connector, bridgeData.execPayload, bridgeData.options
        );

        emit Bridged(wallet, asset, amount);
    }
}

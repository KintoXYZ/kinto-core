// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin-5.0.1/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBridge} from "@kinto-core/interfaces/bridger/IBridge.sol";

/**
 * @title Mining Adaptor
 * @notice Bridges K tokens from Ethereum to Kinto
 */
contract MiningAdaptor {
    using SafeERC20 for IERC20;

    address public constant KINTO = 0x2367C8395a283f0285c6E312D5aA15826f1fEA25;
    address public constant KINTO_MINING_CONTRACT = 0xD157904639E89df05e89e0DabeEC99aE3d74F9AA;
    uint256 public constant MSG_GAS_LIMIT = 500_000;
    address public constant VAULT = 0x2f87464d5F5356dB350dcb302FE28040986783a7;
    address public constant CONNECTOR = 0xA7384185a6428e6B0D33199256fE67b6fA5D8e40;

    function bridge() external payable {
        // Bridge entire balance
        uint256 balance = IERC20(KINTO).balanceOf(address(this));
        // Approve max allowance to save on gas for future transfers
        if (IERC20(KINTO).allowance(address(this), VAULT) < balance) {
            IERC20(KINTO).forceApprove(VAULT, type(uint256).max);
        }

        // Bridge the tokens to Kinto
        IBridge(VAULT).bridge{value: msg.value}(
            KINTO_MINING_CONTRACT, balance, MSG_GAS_LIMIT, CONNECTOR, bytes(""), bytes("")
        );
    }
}

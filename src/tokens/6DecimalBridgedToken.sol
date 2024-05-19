// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {BridgedToken as BT} from "./BridgedToken.sol";
/**
 * @title BridgedToken
 * @dev Inherits from BridgedToken but overrides decimals to be 6. To be used on tokens with 6 decimals (e.g USDC).
 */

contract BridgedToken is BT {
    function decimals() public view override returns (uint8) {
        return 6;
    }
}

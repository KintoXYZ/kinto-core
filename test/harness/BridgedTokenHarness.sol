// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {BridgedToken} from "../../src/tokens/bridged/BridgedToken.sol";

contract BridgedTokenHarness is BridgedToken {
    constructor(uint8 _decimals) BridgedToken(_decimals) {}

    function answer() external pure returns (uint256) {
        return 42;
    }
}

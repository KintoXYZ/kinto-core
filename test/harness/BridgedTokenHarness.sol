// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {BridgedToken} from "../../src/tokens/BridgedToken.sol";

contract BridgedTokenHarness is BridgedToken {
    function answer() external pure returns (uint256) {
        return 42;
    }
}

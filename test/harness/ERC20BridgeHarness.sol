// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ERC20Bridge} from "../../src/tokens/ERC20Bridge.sol";

contract ERC20BridgeHarness is ERC20Bridge {
    function answer() external pure returns (uint256) {
        return 42;
    }
}

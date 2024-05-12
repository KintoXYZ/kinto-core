// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {EngenBadges} from "../../src/tokens/EngenBadges.sol";

contract EngenBadgesHarness is EngenBadges {
    function answer() external pure returns (uint256) {
        return 42;
    }
}

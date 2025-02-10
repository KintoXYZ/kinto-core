// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8;

import {EntryPoint} from "@aa/core/EntryPoint.sol";
import {PackedUserOperation} from "@aa/interfaces/PackedUserOperation.sol";

interface IInflator {
    function inflate(bytes calldata compressed)
        external
        view
        returns (PackedUserOperation[] memory ops, address payable beneficiary);
}

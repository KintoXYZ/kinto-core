// SPDX-License-Identifier: MIT
pragma solidity >=0.8;

import "@aa/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@aa/interfaces/PackedUserOperation.sol";

interface IOpInflator {
    function inflate(bytes calldata compressed) external view returns (PackedUserOperation memory op);
}

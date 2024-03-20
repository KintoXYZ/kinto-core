// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8;

import "@aa/interfaces/IEntryPoint.sol";

interface IOpInflator {
    function inflate(bytes calldata compressed) external view returns (UserOperation memory op);
}

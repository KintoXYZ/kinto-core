// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8;

import "./IKintoEntryPoint.sol";

interface IInflator {
    function inflate(bytes calldata compressed)
        external
        view
        returns (UserOperation[] memory ops, address payable beneficiary);
}

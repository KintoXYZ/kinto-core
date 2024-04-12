// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import { IEntryPoint } from "@aa/interfaces/IEntryPoint.sol";
import { ISponsorPaymaster } from "src/interfaces/ISponsorPaymaster.sol";

contract SimpleReentrantEntryPoint {
    IEntryPoint public immutable entryPoint;
    uint256 private _value;

    constructor(IEntryPoint _entryPoint) {
        entryPoint = _entryPoint;
    }

    receive() payable external {
        (bool success, ) = address(entryPoint).call{value : _value}("");
        success == true;
    }
}

contract SimpleReentrantPaymaster {
    ISponsorPaymaster public immutable paymaster;
    uint256 private _value;

    constructor(ISponsorPaymaster _paymaster) {
        paymaster = _paymaster;
    }

    receive() payable external {
        paymaster.addDepositFor{value : _value}(address(this));
    }
}

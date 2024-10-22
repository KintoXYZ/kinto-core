// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {KintoID} from "@kinto-core/KintoID.sol";

contract KintoIdHarness is KintoID {
    constructor(address _walletFactory, address _faucet) KintoID(_walletFactory, _faucet) {}

    function isSanctionsMonitored(uint32) public view virtual override returns (bool) {
        return true;
    }
}

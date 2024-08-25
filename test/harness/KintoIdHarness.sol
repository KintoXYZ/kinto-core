// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {KintoID} from "@kinto-core/KintoID.sol";

contract KintoIdHarness is KintoID {
    constructor(address _walletFactory) KintoID(_walletFactory) {}

    function isSanctionsMonitored(uint32 _days) public view virtual override returns (bool) {
        return true;
    }
}

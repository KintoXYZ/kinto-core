// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IBridge} from "@kinto-core/interfaces/bridger/IBridge.sol";

contract BridgeMock is IBridge {
    function bridge(address, uint256, uint256, address, bytes calldata, bytes calldata) external payable {}

    function receiveInbound(uint32, bytes memory) external payable {}

    function retry(address, bytes32) external {}
}

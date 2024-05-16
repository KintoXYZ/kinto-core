// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IBridge {
    function bridge(
        address receiver_,
        uint256 amount_,
        uint256 msgGasLimit_,
        address connector_,
        bytes calldata execPayload_,
        bytes calldata options_
    ) external payable;

    function receiveInbound(uint32 siblingChainSlug_, bytes memory payload_) external payable;

    function retry(address connector_, bytes32 messageId_) external;
}

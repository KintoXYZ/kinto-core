// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IConnector {
    function outbound(
        uint256 msgGasLimit_,
        bytes memory payload_,
        bytes memory options_
    ) external payable returns (bytes32 messageId_);

    function siblingChainSlug() external view returns (uint32);

    function getMinFees(
        uint256 msgGasLimit_,
        uint256 payloadSize_
    ) external view returns (uint256 totalFees);

    function getMessageId() external view returns (bytes32);
}

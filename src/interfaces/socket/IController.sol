// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IController {
    function identifierCache(
        bytes32 messageId_
    ) external payable returns (bytes memory cache);

    function connectorCache(
        address connector_
    ) external payable returns (bytes memory cache);
}

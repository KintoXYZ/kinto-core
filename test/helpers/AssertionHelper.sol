// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

abstract contract AssertionHelper is Test {
    // selector reasons
    function assertRevertReasonEq(bytes4 expectedSelector) internal {
        bool foundMatchingRevert = false;
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            // check if this is the correct event
            if (
                logs[i].topics[0] == keccak256("UserOperationRevertReason(bytes32,address,uint256,bytes)")
                    || logs[i].topics[0] == keccak256("PostOpRevertReason(bytes32,address,uint256,bytes)")
            ) {
                (, bytes memory revertReasonBytes) = abi.decode(logs[i].data, (uint256, bytes));

                // check if the revertReasonBytes match the expected selector
                if (revertReasonBytes.length >= 4) {
                    bytes4 actualSelector = bytes4(revertReasonBytes[0]) | (bytes4(revertReasonBytes[1]) >> 8)
                        | (bytes4(revertReasonBytes[2]) >> 16) | (bytes4(revertReasonBytes[3]) >> 24);

                    if (actualSelector == expectedSelector) {
                        foundMatchingRevert = true;
                        break; // exit the loop if a match is found
                    }
                }
            }
        }

        if (!foundMatchingRevert) {
            revert("Expected revert reason did not match");
        }
    }

    // string reasons
    function assertRevertReasonEq(bytes memory _reason) internal {
        bytes[] memory reasons = new bytes[](1);
        reasons[0] = _reason;
        _assertRevertReasonEq(reasons);
    }

    /// @dev if 2 or more UserOperationRevertReason events are emitted
    function assertRevertReasonEq(bytes[] memory _reasons) internal {
        _assertRevertReasonEq(_reasons);
    }

    function _assertRevertReasonEq(bytes[] memory _reasons) internal {
        uint256 matchingReverts = 0;
        uint256 idx = 0;
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            // check if this is the correct event
            if (
                logs[i].topics[0] == keccak256("UserOperationRevertReason(bytes32,address,uint256,bytes)")
                    || logs[i].topics[0] == keccak256("PostOpRevertReason(bytes32,address,uint256,bytes)")
            ) {
                (, bytes memory revertReasonBytes) = abi.decode(logs[i].data, (uint256, bytes));

                // check that the revertReasonBytes is long enough (at least 4 bytes for the selector + additional data for the message)
                if (revertReasonBytes.length >= 4) {
                    // remove the first 4 bytes (the function selector)
                    bytes memory errorBytes = new bytes(revertReasonBytes.length - 4);
                    for (uint256 j = 4; j < revertReasonBytes.length; j++) {
                        errorBytes[j - 4] = revertReasonBytes[j];
                    }
                    string memory decodedRevertReason = abi.decode(errorBytes, (string));
                    string[] memory prefixes = new string[](3);
                    prefixes[0] = "SP";
                    prefixes[1] = "KW";
                    prefixes[2] = "EC";

                    // clean revert reason & assert
                    string memory cleanRevertReason = _trimToPrefixAndRemoveTrailingNulls(decodedRevertReason, prefixes);
                    if (keccak256(abi.encodePacked(cleanRevertReason)) == keccak256(abi.encodePacked(_reasons[idx]))) {
                        matchingReverts++;
                        if (_reasons.length > 1) {
                            idx++; // if there's only one reason, we always use the same one
                        }
                    }
                }
            }
        }

        if (matchingReverts < _reasons.length) {
            revert("Expected revert reason did not match");
        }
    }

    function _trimToPrefixAndRemoveTrailingNulls(string memory revertReason, string[] memory prefixes)
        internal
        pure
        returns (string memory)
    {
        bytes memory revertBytes = bytes(revertReason);
        uint256 meaningfulLength = revertBytes.length;
        if (meaningfulLength == 0) return revertReason;

        // find the actual end of the meaningful content
        for (uint256 i = revertBytes.length - 1; i >= 0; i--) {
            if (revertBytes[i] != 0) {
                meaningfulLength = i + 1;
                break;
            }
            if (i == 0) break; // avoid underflow
        }
        // trim until one of the prefixes
        for (uint256 j = 0; j < revertBytes.length; j++) {
            for (uint256 k = 0; k < prefixes.length; k++) {
                bytes memory prefixBytes = bytes(prefixes[k]);
                if (j + prefixBytes.length <= meaningfulLength) {
                    bool matched = true;
                    for (uint256 l = 0; l < prefixBytes.length; l++) {
                        if (revertBytes[j + l] != prefixBytes[l]) {
                            matched = false;
                            break;
                        }
                    }
                    if (matched) {
                        // create a new trimmed and cleaned string
                        bytes memory trimmedBytes = new bytes(meaningfulLength - j);
                        for (uint256 m = j; m < meaningfulLength; m++) {
                            trimmedBytes[m - j] = revertBytes[m];
                        }
                        return string(trimmedBytes);
                    }
                }
            }
        }

        // if no prefix is found or no meaningful content, return the original string
        return revertReason;
    }
}

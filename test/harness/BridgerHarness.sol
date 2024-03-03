// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Bridger} from "../../src/bridger/Bridger.sol";

contract BridgerHarness is Bridger {
    constructor(address _l2Vault) Bridger(_l2Vault) {}

    function domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function hashSignatureData(SignatureData memory signatureData) external pure returns (bytes32) {
        return _hashSignatureData(signatureData);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Bridger} from "../../src/bridger/Bridger.sol";

contract BridgerHarness is Bridger {
    constructor(address router, address usdc, address weth, address dai, address usde, address sUsde, address wstEth)
        Bridger(router, usdc, weth, dai, usde, sUsde, wstEth)
    {}

    function domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function hashSignatureData(SignatureData calldata signatureData) external pure returns (bytes32) {
        return _hashSignatureData(signatureData);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/interfaces/IKintoEntryPoint.sol";
import "../../src/interfaces/IKintoID.sol";
import "../../src/interfaces/IKintoAppRegistry.sol";

import {KintoWallet} from "../../src/wallet/KintoWallet.sol";

contract KintoWalletHarness is KintoWallet {
    constructor(IEntryPoint __entryPoint, IKintoID _kintoID, IKintoAppRegistry _kintoApp, IKintoWalletFactory _factory)
        KintoWallet(__entryPoint, _kintoID, _kintoApp, _factory)
    {}

    function validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
        public
        returns (uint256 validationData)
    {
        return _validateSignature(userOp, userOpHash);
    }
}

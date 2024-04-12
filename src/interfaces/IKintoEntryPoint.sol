// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@aa/interfaces/IEntryPoint.sol";

interface IKintoEntryPoint is IEntryPoint {
    function walletFactory() external view returns (address);

    // Admin
    function setWalletFactory(address _walletFactory) external;
}

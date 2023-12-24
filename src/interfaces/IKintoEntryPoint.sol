// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '@aa/interfaces/IEntryPoint.sol';

interface IKintoEntryPoint is IEntryPoint {

  function walletFactory() external view returns (address);

  function kintoOwner() external view returns (address);

  function isValidBeneficiary(address _beneficiary) external view returns (bool);

  // Admin
  function setWalletFactory(address _walletFactory) external;

  function setBeneficiary(address _beneficiary, bool _isValid) external;

  function changeKintoOwner(address _newOwner) external;
}
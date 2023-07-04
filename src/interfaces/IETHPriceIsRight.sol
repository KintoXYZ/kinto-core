// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/utils/structs/BitMapsUpgradeable.sol";

interface IETHPriceIsRight {

    /* ============ State Change ============ */

    function enterGuess(uint256 _price) external;

    /* ============ Basic Viewers ============ */

    function guesses(address _account) external view returns (uint256);

    function maxGuess() external view returns (uint256);

    function minGuess() external view returns (uint256);

    function avgGuess() external view returns (uint256);

    function guessCount() external view returns (uint256);

    // ignore this linter warning, it's a false positive
    // solhint-disable-next-line func-name-mixedcase
    function END_ENTER_TIMESTAMP() external view returns (uint256);
}
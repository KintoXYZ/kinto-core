// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IETHPriceIsRight {
    /* ============ Errors ============ */

    error EnteringClosed();
    error InvalidGuess();

    /* ============ State Change ============ */

    function enterGuess(uint256 _price) external;

    /* ============ Basic Viewers ============ */

    function guesses(address _account) external view returns (uint256);

    function maxGuess() external view returns (uint256);

    function minGuess() external view returns (uint256);

    function avgGuess() external view returns (uint256);

    function guessCount() external view returns (uint256);

    // ignore this linter warning, it's a false positive
    function END_ENTER_TIMESTAMP() external view returns (uint256);
}

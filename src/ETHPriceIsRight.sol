// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {IETHPriceIsRight} from './interfaces/IETHPriceIsRight.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title ETHPriceIsRight
 * @dev The Kinto demo application to guess the price of ETH at the end of 2024
 * @dev Guess must be entered before the end of 2023
 */
contract ETHPriceIsRight is Ownable, IETHPriceIsRight{

    /* ============ Events ============ */
    event Guess(address indexed _to, uint _guess, uint256 _timestamp);

    /* ============ Constants ============ */
    uint public constant override END_ENTER_TIMESTAMP = 1735689601; // January 1st 2024

    /* ============ State Variables ============ */
    mapping(address => uint) public override guesses;
    uint public override maxGuess = 0;
    uint public override minGuess = 0;
    uint public override avgGuess = 0;
    uint public override guessCount = 0;

    constructor(){}

    /**
    * @dev Allows users to enter a guess of the price of ETH
    */
    function enterGuess(uint256 guess) external override {
        require(block.timestamp < END_ENTER_TIMESTAMP, 'You cannot enter guesses anymore');
        require(guess > 0, 'Guess must be greater than 0');
        // Remove previous guess from the calculation if any
        if (guesses[msg.sender] > 0) {
            guessCount--;
            if (guessCount > 0) {
                avgGuess = (avgGuess * guessCount - guesses[msg.sender]) / guessCount;
            }
        } 
        // Add new guess
        guessCount++;
        avgGuess = (avgGuess * (guessCount - 1) + guess) / guessCount;
        guesses[msg.sender] = guess;
        if (guess > maxGuess) {
            maxGuess = guess;
        }
        if (guess < minGuess || minGuess == 0) {
            minGuess = guess;
        }
        emit Guess(msg.sender, guess, block.timestamp);
    }
}
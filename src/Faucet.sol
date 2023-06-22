// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFaucet} from "./interfaces/IFaucet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Faucet
 * @dev The Kinto Faucet gives a bit of ETH to users to pay for gas fees
 */
contract Faucet is Ownable, IFaucet{

    /* ============ Events ============ */
    event Claim(address indexed _to, uint256 _timestamp);

    /* ============ Constants ============ */
    uint public constant CLAIM_AMOUNT = 1 ether / 200;
    uint public constant FAUCET_AMOUNT = 1 ether;

    /* ============ State Variables ============ */
    mapping(address => bool) public override claimed;
    bool public active;

    constructor(){}

    /**
    * @dev Allows users to claim KintoETH from the smart contract's faucet once per account
    */
    function claimKintoETH() external override {
        require(active, "Faucet is not active");
        require(!claimed[msg.sender], "You have already claimed your KintoETH");
        claimed[msg.sender] = true;
        payable(msg.sender).transfer(CLAIM_AMOUNT);
        if (address(this).balance < CLAIM_AMOUNT) {
            active = false;
        }
        emit Claim(msg.sender, block.timestamp);
    }

    /**
    * @dev Function to withdraw all eth by owner
    */
    function withdrawAll() external override onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /**
    * @dev Function to start the faucet
    */
    function startFaucet() payable external override onlyOwner {
        require(msg.value >= FAUCET_AMOUNT, 'Not enough ETH to start faucet');
        active = true;
    }

    /**
    * @dev Allows the contract to receive Ether
    */
    receive() external payable {}
}
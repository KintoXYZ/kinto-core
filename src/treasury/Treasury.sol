// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/ITreasury.sol";

/**
 * @title Kinto Treasury
 * @author Kinto
 * Contract that will receive the fees earned by the chain.
 * Governance will be able to send funds from the treasury.
 */
contract Treasury is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard, ITreasury {
    using SafeERC20 for IERC20;
    using Address for address;

    /* ============ Events ============ */
    event TreasuryFundsSent(address _asset, uint256 _amount, address _to);

    /* ============ State Variables ============ */

    /* ============ Constructor & Upgrades ============ */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Upgrade calling `upgradeTo()`
     */
    function initialize() external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        _transferOwnership(msg.sender);
    }

    /**
     * @dev Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the factory is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner { }

    /* ============ External Functions ============ */

    /**
     * GOVERNANCE FUNCTION: Send an asset amount to an address
     *
     * @param _asset            Address of the asset to send
     * @param _amount           Amount to send of the asset
     * @param _to               Address to send the assets to
     */
    function sendTreasuryFunds(address _asset, uint256 _amount, address _to) public override onlyOwner nonReentrant {
        require(_asset != address(0), "Asset must exist");
        require(_to != address(0), "Target address must exist");

        IERC20(_asset).safeTransfer(_to, _amount);

        emit TreasuryFundsSent(_asset, _amount, _to);
    }

    /**
     * GOVERNANCE FUNCTION: Send an ETH amount to an address
     *
     * @param _amount           Amount to send of the asset
     * @param _to               Address to send the assets to
     */
    function sendTreasuryETH(uint256 _amount, address payable _to) external override onlyOwner nonReentrant {
        require(_to != address(0), "Target address must exist");
        require(address(this).balance >= _amount, "Not enough funds in treasury");

        Address.sendValue(_to, _amount);

        emit TreasuryFundsSent(address(0), _amount, _to);
    }

    /**
     * GOVERNANCE FUNCTION: Send multiple asset amounts to multiple addresses
     *
     * @param _assets           Addresses of the assets to send
     * @param _amounts          Amounts to send of the assets
     * @param _tos              Addresses to send the assets to
     */
    function batchSendTreasuryFunds(address[] calldata _assets, uint256[] calldata _amounts, address[] calldata _tos)
        external
        override
        onlyOwner
        nonReentrant
    {
        require(_assets.length == _amounts.length, "Arrays must be the same length");
        require(_assets.length == _tos.length, "Arrays must be the same length");

        for (uint256 i = 0; i < _assets.length; i++) {
            sendTreasuryFunds(_assets[i], _amounts[i], _tos[i]);
        }
    }

    // Can receive ETH
    // solhint-disable-next-line
    receive() external payable {}
}

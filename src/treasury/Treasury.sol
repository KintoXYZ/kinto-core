// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {OwnableUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin-5.0.1/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title Kinto Treasury
 * @author Kinto
 * @notice Contract that will receive the fees earned by the chain.
 * Governance will be able to send funds from the treasury.
 */
contract Treasury is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
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
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    /**
     * @notice Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the factory is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {}

    /* ============ External Functions ============ */

    /**
     * @notice GOVERNANCE FUNCTION: Send an asset amount to an address
     *
     * @param _asset            Address of the asset to send
     * @param _amount           Amount to send of the asset
     * @param _to               Address to send the assets to
     */
    function sendFunds(address _asset, uint256 _amount, address _to) public onlyOwner nonReentrant {
        require(_asset != address(0), "Asset must exist");
        require(_to != address(0), "Target address must exist");

        IERC20(_asset).safeTransfer(_to, _amount);

        emit TreasuryFundsSent(_asset, _amount, _to);
    }

    /**
     * @notice GOVERNANCE FUNCTION: Send an ETH amount to an address
     *
     * @param _amount           Amount to send of the asset
     * @param _to               Address to send the assets to
     */
    function sendETH(uint256 _amount, address payable _to) external onlyOwner nonReentrant {
        require(_to != address(0), "Target address must exist");
        require(address(this).balance >= _amount, "Not enough funds in treasury");

        Address.sendValue(_to, _amount);

        emit TreasuryFundsSent(address(0), _amount, _to);
    }

    /**
     * @notice GOVERNANCE FUNCTION: Send multiple asset amounts to multiple addresses
     *
     * @param _assets           Addresses of the assets to send
     * @param _amounts          Amounts to send of the assets
     * @param _tos              Addresses to send the assets to
     */
    function batchSendFunds(address[] calldata _assets, uint256[] calldata _amounts, address[] calldata _tos)
        external
        onlyOwner
        nonReentrant
    {
        require(_assets.length == _amounts.length, "Arrays must be the same length");
        require(_assets.length == _tos.length, "Arrays must be the same length");

        for (uint256 i = 0; i < _assets.length; i++) {
            sendFunds(_assets[i], _amounts[i], _tos[i]);
        }
    }

    // Can receive ETH
    // solhint-disable-next-line
    receive() external payable {}
}

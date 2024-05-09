// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IViewer} from "@kinto-core/interfaces/IViewer.sol";

/**
 * @title Viewer Smart Contract
 * @dev This contract serves as a view-only interface that allows querying token balances for a specified address.
 *      It is upgradeable using the UUPS pattern and is owned by a single owner.
 */
contract Viewer is Initializable, UUPSUpgradeable, OwnableUpgradeable, IViewer {
    /// @dev Initializes the contract in a disabled state to prevent its use without proxy.
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract setting up the owner and making it ready for upgrades.
     *      This function can only be called once, due to the `initializer` modifier.
     */
    function initialize() external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        _transferOwnership(msg.sender);
    }

    /**
     * @dev Overrides the UUPSUpgradeable's _authorizeUpgrade to add security by restricting
     *      upgrade authorization to only the owner of the contract.
     * @param newImplementation Address of the new contract implementation to which upgrade will happen.
     */
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        // Optional: Add custom logic for upgrade authorization or validation of new implementation
        (newImplementation); // This line prevents unused variable warning.
    }

    /**
     * @notice Retrieves the ERC20 token balances for a specific target address.
     * @dev This view function allows fetching balances for multiple tokens in a single call,
            which can save considerable gas over multiple calls.
     * @param tokens An array of token addresses to query balances for.
     * @param target The address whose balances will be queried.
     * @return balances An array of balances corresponding to the array of tokens provided.
     */
    function getBalances(address[] memory tokens, address target) external view returns (uint256[] memory balances) {
        balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = IERC20(tokens[i]).balanceOf(target);
        }
    }
}

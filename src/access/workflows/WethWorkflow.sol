// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Importing the IERC20 interface and SafeERC20 utility from OpenZeppelin
import {IERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin-5.0.1/contracts/utils/Address.sol";
import {IWETH9 as IWETH} from "@token-bridge-contracts/contracts/tokenbridge/libraries/IWETH9.sol";

/**
 * @title WethWorkflow
 * @dev This contract implements basic functionalities to interact with the WETH (Wrapped Ether) contract.
 * It allows for the depositing and withdrawing of Ether in exchange for its wrapped counterpart.
 */
contract WethWorkflow {
    using SafeERC20 for IERC20;
    using Address for address;

    /// @notice Immutable storage of the IWETH interface representing the WETH contract.
    IWETH public immutable weth;

    /**
     * @dev Initializes the contract by setting a specific WETH contract address.
     * @param _weth The address of the WETH contract to interact with.
     */
    constructor(address _weth) {
        require(_weth.isContract(), "Provided address must be a contract.");
        weth = IWETH(_weth);
    }

    /**
     * @notice Deposits Ether and mints wrapped Ether tokens.
     * @dev Caller must send Ether along with the transaction.
     * @param amount The amount of Ether in wei to be wrapped.
     */
    function deposit(uint256 amount) external payable {
        require(msg.value == amount, "Ether sent mismatch with the amount specified.");
        // The deposit is called on the WETH contract using call value to send Ether.
        weth.deposit{value: amount}();
    }

    /**
     * @notice Withdraws Ether by burning wrapped Ether tokens.
     * @dev Caller must have enough WETH tokens to perform the withdrawal.
     * @param amount The amount of wrapped Ether in wei to be unwrapped.
     */
    function withdraw(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0.");
        // Withdraw the specified amount of Ether from the WETH contract.
        weth.withdraw(amount);
    }
}


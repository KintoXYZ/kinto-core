// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * Created following OpenZeppelin Contracts (last updated v5.0.0) (finance/VestingWallet.sol)
 *
 * @dev A vesting wallet is an ownable contract that can receive  ERC-20 tokens, and release these
 * assets to the wallet owner, also referred to as "beneficiary", according to a vesting schedule.
 *
 * Any assets transferred to this contract will follow the vesting schedule as if they were locked from the beginning.
 * Consequently, if the vesting has already started, any amount of tokens sent to this contract will (at least partly)
 * be immediately releasable.
 *
 * By setting the duration to 0, one can configure this contract to behave like an asset timelock that hold tokens for
 * a beneficiary until a specified time.
 *
 * NOTE: Since the wallet is {Ownable}, and ownership can be transferred, it is possible to sell unvested tokens.
 * Preventing this in a smart contract is difficult, considering that: 1) a beneficiary address could be a
 * counterfactually deployed contract, 2) there is likely to be a migration path for EOAs to become contracts in the
 * near future.
 *
 */
contract VestingContract is Ownable {
    event ERC20Released(address indexed beneficiary, uint256 amount);

    address public immutable kintoToken;
    mapping(address => uint256) private _erc20Released;
    mapping(address => uint64) private _start;
    mapping(address => uint64) private _duration;

    /**
     * @dev Sets the sender as the initial owner, the beneficiary as the pending owner, the start timestamp and the
     * vesting duration of the vesting wallet.
     */
    constructor(address token, address beneficiary, uint64 startTimestamp, uint64 durationSeconds) Ownable() {
        _start[beneficiary] = startTimestamp;
        _duration[beneficiary] = durationSeconds;
        kintoToken = token;
    }

    /**
     * @dev Getter for the start timestamp.
     */
    function start(address beneficiary) public view virtual returns (uint256) {
        return _start[beneficiary];
    }

    /**
     * @dev Getter for the vesting duration.
     */
    function duration(address beneficiary) public view virtual returns (uint256) {
        return _duration[beneficiary];
    }

    /**
     * @dev Getter for the end timestamp.
     */
    function end(address beneficiary) public view virtual returns (uint256) {
        return start(beneficiary) + duration(beneficiary);
    }

    /**
     * @dev Amount of token already released
     */
    function released(address beneficiary) public view virtual returns (uint256) {
        return _erc20Released[beneficiary];
    }

    /**
     * @dev Getter for the amount of releasable Kinto tokens. `token` should be the address of an
     * {IERC20} contract.
     */
    function releasable(address beneficiary) public view virtual returns (uint256) {
        return vestedAmount(beneficiary, uint64(block.timestamp)) - released(beneficiary);
    }

    /**
     * @dev Release the tokens that have already vested.
     *
     * Emits a {ERC20Released} event.
     */
    function release(address beneficiary) public virtual {
        uint256 amount = releasable(beneficiary);
        _erc20Released[beneficiary] += amount;
        emit ERC20Released(beneficiary, amount);
        SafeERC20.safeTransfer(IERC20(kintoToken), owner(), amount);
    }

    /**
     * @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
     */
    function vestedAmount(address beneficiary, uint64 timestamp) public view virtual returns (uint256) {
        return _vestingSchedule(
            beneficiary, IERC20(beneficiary).balanceOf(address(this)) + released(kintoToken), timestamp
        );
    }

    /**
     * @dev Virtual implementation of the vesting formula. This returns the amount vested, as a function of time, for
     * an asset given its total historical allocation.
     */
    function _vestingSchedule(address beneficiary, uint256 totalAllocation, uint64 timestamp)
        internal
        view
        virtual
        returns (uint256)
    {
        if (timestamp < start(beneficiary)) {
            return 0;
        } else if (timestamp >= end(beneficiary)) {
            return totalAllocation;
        } else {
            return (totalAllocation * (timestamp - start(beneficiary))) / duration(beneficiary);
        }
    }
}

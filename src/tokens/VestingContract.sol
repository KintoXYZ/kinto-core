// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../interfaces/IVestingContract.sol";
import "@openzeppelin-5.0.1/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-5.0.1/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-5.0.1/contracts/access/Ownable.sol";
import "@openzeppelin-5.0.1/contracts/utils/Address.sol";

/**
 * @title VestingContract - To be deployed on ETH mainnet
 * Created following OpenZeppelin Contracts (last updated v5.0.0) (finance/VestingWallet.sol)
 *
 * @dev A vesting wallet is an ownable contract that can receive  ERC-20 tokens, and release these
 * assets to "beneficiary", according to a vesting schedule and a mandatory one-year lock.
 *
 * Any assets transferred to this contract will follow the vesting schedule as if they were locked from the beginning.
 * Consequently, if the vesting has already started, any amount of tokens sent to this contract will (at least partly)
 * be immediately releasable.
 *
 * By setting the duration to 0, one can configure this contract to behave like an asset timelock that hold tokens for
 * a beneficiary until a specified time + lock time.
 *
 */
contract VestingContract is Ownable, IVestingContract {
    /* ============ Events ============ */
    event ERC20Released(address indexed beneficiary, uint256 amount);

    /* ============ Errors ============ */
    error InLockPeriod();
    error NotEnoughTokens();
    error BeneficiaryAlreadyExists();
    error InvalidAddress();
    error GrantPeriodEnded();
    error NothingToRelease();
    error CantRemoveBeneficiary();
    error ArrayLengthMistmatch();

    /* ============ State variables============ */

    uint256 public constant override LOCK_PERIOD = 365 days;
    address public immutable override kintoToken;

    mapping(address => uint256) private _erc20Released;
    mapping(address => uint256) private _grant;
    mapping(address => uint256) private _start;
    mapping(address => uint256) private _duration;

    uint256 public override totalAllocated;
    uint256 public override totalReleased;

    /* ============ Constructor ============ */

    /**
     * @dev Sets the sender as the initial owner, the beneficiary as the pending owner, the start timestamp and the
     * vesting duration of the vesting wallet.
     */
    constructor(address token) Ownable(msg.sender) {
        kintoToken = token;
    }

    /* ============ Beneficiary Methods ============ */

    /**
     * @dev Add a new beneficiary to the vesting wallet. The beneficiary will receive the tokens according to the
     * vesting schedule.
     * @param beneficiary Address of the beneficiary to whom vested tokens are transferred
     * @param grantAmount Amount of tokens to be vested
     * @param startTimestamp Timestamp at which the vesting schedule begins
     * @param durationSeconds Duration in seconds of the vesting schedule
     */
    function addBeneficiary(address beneficiary, uint256 grantAmount, uint256 startTimestamp, uint256 durationSeconds)
        external
        override
        onlyOwner
    {
        _addBeneficiary(beneficiary, grantAmount, startTimestamp, durationSeconds);
    }

    /**
     * @dev Add multiple beneficiaries to the vesting wallet. The beneficiaries will receive the tokens according to the
     * vesting schedule.
     * @param beneficiaries Addresses of the beneficiaries to whom vested tokens are transferred
     * @param grantAmounts Amount of tokens to be vested
     * @param startTimestamps Timestamp at which the vesting schedule begins
     * @param durationSeconds Duration in seconds of the vesting schedule
     */
    function addBeneficiaries(
        address[] calldata beneficiaries,
        uint256[] calldata grantAmounts,
        uint256[] calldata startTimestamps,
        uint256[] calldata durationSeconds
    ) external override onlyOwner {
        if (
            beneficiaries.length != grantAmounts.length || beneficiaries.length != startTimestamps.length
                || beneficiaries.length != durationSeconds.length
        ) revert ArrayLengthMistmatch();
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            _addBeneficiary(beneficiaries[i], grantAmounts[i], startTimestamps[i], durationSeconds[i]);
        }
    }

    /**
     * @dev Updates tokens when a team member of advisor leaves early.
     * The beneficiary will no longer be able to claim the tokens
     * that have not been released yet.
     * @param beneficiary Address of the beneficiary to be finished
     */
    function earlyLeave(address beneficiary) external override onlyOwner {
        if (block.timestamp > _start[beneficiary] + _duration[beneficiary]) revert GrantPeriodEnded();
        uint256 vested = vestedAmount(beneficiary, uint64(block.timestamp));
        uint256 difference = _grant[beneficiary] - vested;
        _grant[beneficiary] = vested;
        _duration[beneficiary] = block.timestamp - _start[beneficiary];
        totalAllocated -= difference;
    }

    /**
     * @dev Remove a beneficiary from the vesting wallet.
     * The beneficiary will no longer be able to claim the tokens
     * that have not been released yet.
     * @param beneficiary Address of the beneficiary to be removed
     */
    function removeBeneficiary(address beneficiary) external override onlyOwner {
        if (_erc20Released[beneficiary] != 0) revert CantRemoveBeneficiary();
        totalAllocated -= _grant[beneficiary];
        _grant[beneficiary] = 0;
    }

    /* ============ Claim methods ============ */

    /**
     * @dev Release the tokens that have already vested.
     *
     * Emits a {ERC20Released} event.
     */
    function release() external override {
        _release(msg.sender, msg.sender);
    }

    /**
     * @dev Release the tokens that have already vested.
     * @param _beneficiary Address to claim
     *
     * Emits a {ERC20Released} event.
     */
    function emergencyDistribution(address _beneficiary, address _receiver) external override onlyOwner {
        _release(_beneficiary, _receiver);
    }

    /**
     * @dev Add a new beneficiary to the vesting wallet. The beneficiary will receive the tokens according to the
     * vesting schedule.
     * @param beneficiary Address of the beneficiary to whom vested tokens are transferred
     * @param grantAmount Amount of tokens to be vested
     * @param startTimestamp Timestamp at which the vesting schedule begins
     * @param durationSeconds Duration in seconds of the vesting schedule
     */
    function _addBeneficiary(address beneficiary, uint256 grantAmount, uint256 startTimestamp, uint256 durationSeconds)
        private
    {
        if (durationSeconds < LOCK_PERIOD) revert InLockPeriod();
        // revert not enough tokens
        if ((totalAllocated + grantAmount - totalReleased) > IERC20(kintoToken).balanceOf(address(this))) {
            revert NotEnoughTokens();
        }
        if (beneficiary == address(0)) revert InvalidAddress();
        if (_grant[beneficiary] != 0) revert BeneficiaryAlreadyExists();
        _start[beneficiary] = startTimestamp;
        _duration[beneficiary] = durationSeconds;
        _grant[beneficiary] = grantAmount;
        totalAllocated += grantAmount;
    }

    /**
     * @dev Release the tokens that have already vested.
     * @param _beneficiary Address to claim
     *
     * Emits a {ERC20Released} event.
     */
    function _release(address _beneficiary, address _receiver) private {
        uint256 amount = releasable(_beneficiary);
        if (amount == 0) revert NothingToRelease();
        _erc20Released[_beneficiary] += amount;
        emit ERC20Released(_beneficiary, amount);
        totalReleased += amount;
        SafeERC20.safeTransfer(IERC20(kintoToken), _receiver, amount);
    }

    /* ============ Getters ============ */

    /**
     * @dev Getter for the start timestamp.
     */
    function start(address beneficiary) public view override returns (uint256) {
        return _start[beneficiary];
    }

    /**
     * @dev Getter for the unlock timestamp.
     */
    function unlock(address beneficiary) public view override returns (uint256) {
        return _start[beneficiary] + LOCK_PERIOD;
    }

    /**
     * @dev Getter for the vesting duration.
     */
    function duration(address beneficiary) public view override returns (uint256) {
        return _duration[beneficiary];
    }

    /**
     * @dev Getter for the end timestamp.
     */
    function end(address beneficiary) public view override returns (uint256) {
        return start(beneficiary) + duration(beneficiary);
    }

    /**
     * @dev Amount of token already released
     */
    function released(address beneficiary) public view override returns (uint256) {
        return _erc20Released[beneficiary];
    }

    /**
     * @dev Amount of token granted
     */
    function grant(address beneficiary) external view override returns (uint256) {
        return _grant[beneficiary];
    }

    /**
     * @dev Getter for the amount of releasable Kinto tokens. `token` should be the address of an
     * {IERC20} contract.
     */
    function releasable(address beneficiary) public view override returns (uint256) {
        return vestedAmount(beneficiary, uint64(block.timestamp)) - released(beneficiary);
    }

    /**
     * @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
     */
    function vestedAmount(address beneficiary, uint256 timestamp) public view override returns (uint256) {
        return _vestingSchedule(beneficiary, _grant[beneficiary], timestamp);
    }

    /**
     * @dev Virtual implementation of the vesting formula. This returns the amount vested, as a function of time, for
     * an asset given its total historical allocation.
     */
    function _vestingSchedule(address beneficiary, uint256 totalAllocation, uint256 timestamp)
        internal
        view
        returns (uint256)
    {
        if (timestamp < unlock(beneficiary)) {
            return 0;
        } else if (timestamp >= end(beneficiary)) {
            return totalAllocation;
        } else {
            return (totalAllocation * (timestamp - start(beneficiary))) / duration(beneficiary);
        }
    }
}

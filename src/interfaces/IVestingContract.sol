// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IVestingContract {
    /* ============ State Change ============ */
    function addBeneficiary(address beneficiary, uint256 grantAmount, uint256 startTimestamp, uint256 durationSeconds)
        external;

    function addBeneficiaries(
        address[] calldata beneficiaries,
        uint256[] calldata grantAmounts,
        uint256[] calldata startTimestamps,
        uint256[] calldata durationSeconds
    ) external;

    function removeBeneficiary(address beneficiary) external;

    function earlyLeave(address beneficiary) external;

    function release() external;

    function emergencyDistribution(address _beneficiary, address _receiver) external;

    /* ============ Getters  ============ */

    function totalAllocated() external view returns (uint256);

    function totalReleased() external view returns (uint256);

    function LOCK_PERIOD() external view returns (uint256);

    function kintoToken() external view returns (address);

    /* ============ Beneficiary Info  ============ */

    function start(address beneficiary) external view returns (uint256);

    function unlock(address beneficiary) external view returns (uint256);

    function duration(address beneficiary) external view returns (uint256);

    function grant(address beneficiary) external view returns (uint256);

    function releasable(address beneficiary) external view returns (uint256);

    function released(address beneficiary) external view returns (uint256);

    function end(address beneficiary) external view returns (uint256);

    function vestedAmount(address beneficiary, uint256 timestamp) external view returns (uint256);
}

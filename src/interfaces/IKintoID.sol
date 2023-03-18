// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/utils/structs/BitMapsUpgradeable.sol";

interface IKintoID {

    /* ============ Structs ============ */

    struct Metadata {
        uint256 mintedAt;
        uint256 updatedAt;
        uint8 sanctionsCount;
        bool individual;
        BitMapsUpgradeable.BitMap traits;
        BitMapsUpgradeable.BitMap sanctions;
    }

    struct SignatureData {
        address signer;
        address account;
        uint256 nonce;
        uint256 expiresAt;
        bytes signature;
    }

    /* ============ State Change ============ */


    function mintIndividualKyc(SignatureData calldata _signatureData, uint8[] memory _traits) external;

    function mintCompanyKyc(SignatureData calldata _signatureData, uint8[] memory _traits) external;

    function burnKYC(SignatureData calldata _signatureData) external;

    function setURI(string memory newuri) external;

    function addTrait(address _account, uint8 _traitId) external;

    function removeTrait(address _account, uint8 _traitId) external;

    function addSanction(address _account, uint8 _countryId) external;

    function removeSanction(address _account, uint8 _countryId) external;

    /* ============ Basic Viewers ============ */

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function isKYC(address _account) external view returns (bool);

    function isSanctionsMonitored(uint32 _days) external view returns (bool);

    function isSanctionsSafe(address _account) external view returns (bool);

    function isSanctionsSafeIn(address _account, uint8 _countryId) external view returns (bool);

    function isCompany(address _account) external view returns (bool);

    function isIndividual(address _account) external view returns (bool);

    function mintedAt(address _account) external view returns (uint256);

    function hasTrait(address _account, uint8 index) external view returns (bool);

    function traits(address _account) external view returns (bool[] memory);

    /* ============ Constants and attrs ============ */

    function KYC_TOKEN_ID() external view returns (uint8);

    function KYC_PROVIDER_ROLE() external view returns (bytes32);

    function lastMonitoredAt() external view returns (uint256);

}

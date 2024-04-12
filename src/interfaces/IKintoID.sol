// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/utils/structs/BitMapsUpgradeable.sol";

interface IKintoID {
    /* ============ Errors ============ */
    error BalanceNotZero();
    error MethodNotAllowed(string reason);
    error NothingToBurn();
    error LengthMismatch();
    error AccountsAmountExceeded();
    error KYCRequired();
    error SignatureExpired();
    error InvalidNonce();
    error InvalidProvider();
    error SignerNotEOA();
    error OnlyMintBurnOrTransfer();
    error InvalidSigner();

    /* ============ Structs ============ */

    struct Metadata {
        uint256 mintedAt;
        uint256 updatedAt;
        uint8 sanctionsCount;
        bool individual;
        BitMapsUpgradeable.BitMap traits;
        BitMapsUpgradeable.BitMap sanctions; // Follows ISO-3661 numeric codes https://en.wikipedia.org/wiki/ISO_3166-1_numeric
    }

    struct SignatureData {
        address signer;
        uint256 nonce;
        uint256 expiresAt;
        bytes signature;
    }

    struct MonitorUpdateData {
        bool isTrait; // otherwise sanction
        bool isSet; // otherwise remove
        uint16 index;
    }

    /* ============ State Change ============ */

    function mintIndividualKyc(SignatureData calldata _signatureData, uint16[] calldata _traits) external;

    function mintCompanyKyc(SignatureData calldata _signatureData, uint16[] calldata _traits) external;

    function burnKYC(SignatureData calldata _signatureData) external;

    function transferOnRecovery(address _from, address _to) external;

    function addTrait(address _account, uint16 _traitId) external;

    function removeTrait(address _account, uint16 _traitId) external;

    function addSanction(address _account, uint16 _countryId) external;

    function removeSanction(address _account, uint16 _countryId) external;

    function monitor(address[] calldata _accounts, MonitorUpdateData[][] calldata _traitsAndSanctions) external;

    /* ============ Basic Viewers ============ */

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function isKYC(address _account) external view returns (bool);

    function isSanctionsMonitored(uint32 _days) external view returns (bool);

    function isSanctionsSafe(address _account) external view returns (bool);

    function isSanctionsSafeIn(address _account, uint16 _countryId) external view returns (bool);

    function isCompany(address _account) external view returns (bool);

    function isIndividual(address _account) external view returns (bool);

    function mintedAt(address _account) external view returns (uint256);

    function hasTrait(address _account, uint16 index) external view returns (bool);

    function traits(address _account) external view returns (bool[] memory);

    /* ============ Constants and attrs ============ */

    function KYC_PROVIDER_ROLE() external view returns (bytes32);

    function UPGRADER_ROLE() external view returns (bytes32);

    function lastMonitoredAt() external view returns (uint256);

    function nonces(address _account) external view returns (uint256);

    function recoveryTargets(address _from) external view returns (address);

    function domainSeparator() external view returns (bytes32);

    function walletFactory() external view returns (address);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/utils/structs/BitMapsUpgradeable.sol";

interface IKintoID {
    /* ============ Errors ============ */

    /// @notice Thrown when trying to interact with an account that has a positive balance
    error BalanceNotZero();

    /// @notice Thrown when trying to burn a non-existent token
    error NothingToBurn();

    /// @notice Thrown when arrays have mismatched lengths
    error LengthMismatch();

    /// @notice Thrown when monitoring update exceeds maximum allowed accounts
    error AccountsAmountExceeded();

    /// @notice Thrown when trying to confirm a sanction for an account with no active sanctions
    error NoActiveSanction(address account);

    /// @notice Thrown when an account lacks required KYC verification
    error KYCRequired();

    /// @notice Thrown when signature verification fails
    error InvalidSigner();

    /// @notice Thrown when the signature has expired
    error SignatureExpired();

    /// @notice Thrown when the nonce is invalid
    error InvalidNonce();

    /// @notice Thrown when the sender is not an authorized KYC provider
    error InvalidProvider();

    /// @notice Thrown when the signer is a contract instead of an EOA
    error SignerNotEOA();

    /// @notice Thrown when a disallowed method is called
    error MethodNotAllowed(string message);

    /// @notice Thrown when attempting unauthorized token transfers
    error OnlyMintBurnOrTransfer();

    /// @notice Thrown when attempting to add or removing sanctions during exit widnow period
    error ExitWindowPeriod(address user, uint256 sanctionedAt);

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

    function isSanctionsMonitored(uint256 _days) external view returns (bool);

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

    function GOVERNANCE_ROLE() external view returns (bytes32);

    function lastMonitoredAt() external view returns (uint256);

    function nonces(address _account) external view returns (uint256);

    function recoveryTargets(address _from) external view returns (address);

    function domainSeparator() external view returns (bytes32);

    function walletFactory() external view returns (address);

    function faucet() external view returns (address);
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "./IKintoID.sol";
import "./IKintoWalletFactory.sol";

interface IKYCViewer {
    /* ============ Basic Viewers ============ */

    function isKYC(address _address) external view returns (bool);

    function isSanctionsSafe(address _account) external view returns (bool);

    function isSanctionsSafeIn(address _account, uint16 _countryId) external view returns (bool);

    function isCompany(address _account) external view returns (bool);

    function isIndividual(address _account) external view returns (bool);

    function hasTrait(address _account, uint8 _traitId) external view returns (bool);

    /* ============ Constants and attrs ============ */

    function kintoID() external view returns (IKintoID);

    function walletFactory() external view returns (IKintoWalletFactory);
}

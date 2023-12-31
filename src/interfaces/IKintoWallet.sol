// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IEntryPoint } from '@aa/core/BaseAccount.sol';
import { IKintoWalletFactory } from './IKintoWalletFactory.sol';
import { IKintoID } from './IKintoID.sol';

interface IKintoWallet {

    /* ============ Structs ============ */

    /* ============ State Change ============ */

    function execute(address dest, uint256 value, bytes calldata func) external;

    function executeBatch(address[] calldata dest, uint256[] calldata values, bytes[] calldata func) external;

    function setSignerPolicy(uint8 policy) external;

    function resetSigners(address[] calldata newSigners, uint8 policy) external;

    function setFunderWhitelist(address[] calldata newWhitelist, bool[] calldata flags) external;

    function changeRecoverer(address newRecoverer) external;

    function startRecovery() external;

    function finishRecovery(address[] calldata newSigners) external;

    function cancelRecovery() external;

    function approveTokens(
        address app,
        address[] calldata tokens,
        uint256[] calldata amount)
        external;

    function revokeTokens(
        address app,
        address[] calldata tokens)
        external;
    
    function setAppKey(address app, address signer) external;

    function setAppWhitelist(address[] calldata apps, bool[] calldata flags) external;

    /* ============ Basic Viewers ============ */

    function getOwnersCount() external view returns (uint);

    function getNonce() external view returns (uint);

    /* ============ Constants and attrs ============ */

    function kintoID() external view returns (IKintoID);

    function inRecovery() external view returns (uint);

    function owners(uint _index) external view returns (address);

    function recoverer() external view returns (address);

    function funderWhitelist(address funder) external view returns (bool);

    function isFunderWhitelisted(address funder) external view returns (bool);

    function isTokenApproved(address app, address token) external view returns (uint256);

    function appSigner(address app) external view returns (address);

    function appWhitelist(address app) external view returns (bool);

    function signerPolicy() external view returns (uint8);

    /* solhint-disable func-name-mixedcase */
    function MAX_SIGNERS() external view returns (uint8);

    function SINGLE_SIGNER() external view returns (uint8);

    function MINUS_ONE_SIGNER() external view returns (uint8);

    function ALL_SIGNERS() external view returns (uint8);

    function RECOVERY_TIME() external view returns (uint);

}

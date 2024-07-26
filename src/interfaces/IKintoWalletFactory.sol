// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IKintoWallet} from "./IKintoWallet.sol";
import {IKintoID} from "./IKintoID.sol";
import {IKintoAppRegistry} from "./IKintoAppRegistry.sol";
import {IFaucet} from "./IFaucet.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

interface IKintoWalletFactory {
    /* ============ Errors ============ */
    error InvalidImplementation();
    error InvalidInput();
    error KYCRequired();
    error KYCMustNotExist();
    error InvalidWallet(address);
    error InvalidRecoverer(address);
    error OnlyRecoverer(address, address);
    error InvalidWalletOrFunder(address);
    error InvalidSender(address);
    error SendFailed();
    error InvalidTarget(address);
    error NotAdminApproved();
    error OnlyPrivileged(address);
    error DeploymentNotAllowed(string reason);
    error AmountMismatch();
    error EmptyBytecode();

    /* ============ State Change ============ */

    function upgradeAllWalletImplementations(IKintoWallet newImplementationWallet) external;

    function createAccount(address owner, address recoverer, bytes32 salt) external returns (IKintoWallet ret);

    function startWalletRecovery(address payable wallet) external;

    function completeWalletRecovery(address payable wallet, address[] calldata newSigners) external;

    function changeWalletRecoverer(address payable wallet, address _newRecoverer) external;

    function fundWallet(address payable wallet) external payable;

    function claimFromFaucet(address _faucet, IFaucet.SignatureData calldata _signatureData) external;

    function sendMoneyToAccount(address target) external payable;

    function sendMoneyToRecoverer(address wallet, address recoverer) external payable;

    function sendETHToDeployer(address deployer) external payable;

    function sendETHToEOA(address eoa, address app) external payable;

    function approveWalletRecovery(address wallet) external;

    /* ============ Basic Viewers ============ */

    function getAddress(address owner, address recoverer, bytes32 salt) external view returns (address);

    function walletTs(address _account) external view returns (uint256);

    function getWalletTimestamp(address wallet) external view returns (uint256);

    function adminApproved(address wallet) external view returns (bool);

    /* ============ Constants and attrs ============ */

    function kintoID() external view returns (IKintoID);

    function appRegistry() external view returns (IKintoAppRegistry);

    function beacon() external view returns (UpgradeableBeacon);

    function factoryWalletVersion() external view returns (uint256);

    function totalWallets() external view returns (uint256);
}

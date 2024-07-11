// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IKintoWallet} from "./IKintoWallet.sol";
import {IKintoID} from "./IKintoID.sol";
import {IFaucet} from "./IFaucet.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

interface IKintoWalletFactory {
    /* ============ Errors ============ */
    error InvalidImplementation();
    error InvalidInput();
    error KYCRequired();
    error KYCMustNotExist();
    error InvalidWallet();
    error InvalidRecoverer();
    error OnlyRecoverer();
    error InvalidWalletOrFunder();
    error InvalidSender();
    error SendFailed();
    error InvalidFaucet();
    error InvalidTarget();
    error NotAdminApproved();
    error OnlyPrivileged();
    error DeploymentNotAllowed(string reason);
    error AmountMismatch();
    error EmptyBytecode();

    /* ============ State Change ============ */

    function upgradeAllWalletImplementations(IKintoWallet newImplementationWallet) external;

    function createAccount(address owner, address recoverer, bytes32 salt) external returns (IKintoWallet ret);

    function deployContract(address contractOwner, uint256 amount, bytes memory bytecode, bytes32 salt)
        external
        payable
        returns (address);

    function startWalletRecovery(address payable wallet) external;

    function setWalletSigners(address[] calldata newSigners, address[] calldata oldSigners) external ;

    function completeWalletRecovery(address payable wallet, address[] calldata newSigners) external;

    function changeWalletRecoverer(address payable wallet, address _newRecoverer) external;

    function fundWallet(address payable wallet) external payable;

    function claimFromFaucet(address _faucet, IFaucet.SignatureData calldata _signatureData) external;

    function sendMoneyToAccount(address target) external payable;

    function sendMoneyToRecoverer(address wallet, address recoverer) external payable;

    function writeL2Deposit(address depositor, address assetL2, uint256 amount) external;

    function approveWalletRecovery(address wallet) external;

    /* ============ Basic Viewers ============ */

    function getSignerWallets(address signer) external view returns (address[] memory) ;

    function getAddress(address owner, address recoverer, bytes32 salt) external view returns (address);

    function getContractAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address);

    function walletTs(address _account) external view returns (uint256);

    function getWalletTimestamp(address wallet) external view returns (uint256);

    function adminApproved(address wallet) external view returns (bool);

    /* ============ Constants and attrs ============ */

    function kintoID() external view returns (IKintoID);

    function beacon() external view returns (UpgradeableBeacon);

    function factoryWalletVersion() external view returns (uint256);

    function totalWallets() external view returns (uint256);
}

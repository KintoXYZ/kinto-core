// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IKintoWallet} from "./IKintoWallet.sol";
import {IKintoID} from "./IKintoID.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

interface IKintoWalletFactory {
    /* ============ Structs ============ */

    /* ============ State Change ============ */

    function upgradeAllWalletImplementations(IKintoWallet newImplementationWallet) external;

    function createAccount(address owner, address recoverer, uint256 salt) external returns (IKintoWallet ret);

    function deployContract(address contractOwner, uint256 amount, bytes memory bytecode, bytes32 salt)
        external
        payable
        returns (address);

    function startWalletRecovery(address payable wallet) external;

    function completeWalletRecovery(address payable wallet, address[] calldata newSigners) external;

    function changeWalletRecoverer(address payable wallet, address _newRecoverer) external;

    function fundWallet(address payable wallet) external payable;

    /* ============ Basic Viewers ============ */

    function getAddress(address owner, address recoverer, uint256 salt) external view returns (address);

    function getContractAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address);

    function walletTs(address _account) external view returns (uint256);

    function getWalletTimestamp(address wallet) external view returns (uint256);

    /* ============ Constants and attrs ============ */

    function kintoID() external view returns (IKintoID);

    function beacon() external view returns (UpgradeableBeacon);

    function factoryWalletVersion() external view returns (uint256);

    function totalWallets() external view returns (uint256);
}

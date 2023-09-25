// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IKintoWallet } from './IKintoWallet.sol';
import { IKintoID } from './IKintoID.sol';

interface IKintoWalletFactory {

    /* ============ Structs ============ */

    /* ============ State Change ============ */

    function upgradeWalletImplementation(IKintoWallet newImplementationWallet) external;

    function createAccount(address owner,uint256 salt) external returns (IKintoWallet ret);

    function deployContract(uint amount, bytes memory bytecode, bytes32 salt) external returns (address);

    function startAccountRecovery(address _account) external;
    
    function finishAccountRecovery(address _account, address _newOwner) external;

    /* ============ Basic Viewers ============ */

    function getAddress(address owner,uint256 salt) external view returns (address);

    function getContractAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address);

    function walletVersion(address _account) external view returns (uint256);

    function getWalletVersion(address wallet) external view returns (uint256);

    /* ============ Constants and attrs ============ */

    function kintoID() external view returns (IKintoID);
    
    function factoryOwner() external view returns (address);
    
    function accountImplementation() external view returns (IKintoWallet);
    
    function factoryWalletVersion() external view returns (uint);
    
    function totalWallets() external view returns (uint);

}
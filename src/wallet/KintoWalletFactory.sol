// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import '@openzeppelin/contracts/utils/Create2.sol';
import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';

import '../interfaces/IKintoID.sol';
import './KintoWallet.sol';

/**
 * @title KintoWalletFactory
 * @dev A kinto wallet factory contract for KintoWallet
 *   A UserOperations "initCode" holds the address of the factory, and a method call (to createAccount, in this sample factory).
 *   The factory's createAccount returns the target account address even if it is already installed.
 *   This way, the entryPoint.getSenderAddress() can be called either before or after the account is created.
 */

// TODO: Needs to be upgradeable
contract KintoWalletFactory {

    /* ============ Events ============ */
    event KintoWalletFactoryCreation(address indexed account, address indexed owner, uint version);
    event KintoWalletFactoryUpgraded(address indexed oldImplementation, address indexed newImplementation);

    /* ============ State Variables ============ */
    IKintoID immutable public kintoID;
    address immutable public factoryOwner;

    KintoWallet public accountImplementation;
    mapping (address => uint256) public walletVersion;
    uint256 public factoryWalletVersion;
    uint256 public totalWallets;

    /* ============ Constructor ============ */
    constructor(IEntryPoint _entryPoint, IKintoID _kintoID) {
        accountImplementation = new KintoWallet(_entryPoint, _kintoID);
        kintoID = _kintoID;
        factoryWalletVersion = 1;
        factoryOwner = msg.sender;
    }

    /**
     * @dev Upgrade the wallet implementation
     * @param newImplementationWallet The new implementation
     */
    function upgradeImplementation(KintoWallet newImplementationWallet) public {
        require(msg.sender == factoryOwner, 'only owner');
        require(address(newImplementationWallet) != address(0), 'invalid address');
        factoryWalletVersion++;
        emit KintoWalletFactoryUpgraded(address(accountImplementation), address(newImplementationWallet));
        accountImplementation = newImplementationWallet;
    }

    /**
     *
     * @dev Create an account, and return its address.
     * It returns the address even if the account is already deployed.
     * Note that during UserOperation execution, this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress() would work even after account creation
     * @param owner The owner address
     * @param salt The salt to use for the calculation
     * @return ret address of the account
     */
    function createAccount(address owner,uint256 salt) public returns (KintoWallet ret) {
        address addr = getAddress(owner, salt);
        uint codeSize = addr.code.length;
        if (codeSize > 0) {
            return KintoWallet(payable(addr));
        }
        ret = KintoWallet(payable(new ERC1967Proxy{salt : bytes32(salt)}(
                address(accountImplementation),
                abi.encodeCall(KintoWallet.initialize, (owner))
            )));
        walletVersion[address(ret)] = factoryWalletVersion;
        totalWallets++;
        // Emit event
        emit KintoWalletFactoryCreation(address(ret), owner, factoryWalletVersion);
        require(kintoID.isKYC(owner), 'KYC required');
    }

    /* ============ View Functions ============ */

    /**
     * @dev Gets the version of a current wallet
     * @param wallet The wallet address
     * @return The version of the wallet. 0 if it is not a wallet
     */
    function getWalletVersion(address wallet) external view returns (uint256) {
        return walletVersion[wallet];
    }

    /**
     * @dev Calculates the counterfactual address of this account as it would be returned by createAccount()
     * @param owner The owner address
     * @param salt The salt to use for the calculation
     * @return The address of the account
     */
    function getAddress(address owner,uint256 salt) public view returns (address) {
        return Create2.computeAddress(bytes32(salt), keccak256(abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    address(accountImplementation),
                    abi.encodeCall(KintoWallet.initialize, (owner))
                )
            )));
    }
}

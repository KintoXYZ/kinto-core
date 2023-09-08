// SPDX-License-Identifier: GPL-3.0
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

// TODO: if we want our entry point to allow only our wallets, we can add this check before validating user op:
// require(IUUPSProxy(proxyAddress).implementation() == kintoFactory.accountImplementation(), '');
contract KintoWalletFactory {
    IKintoID immutable public kintoID;
    KintoWallet public accountImplementation;
    address public factoryOwner;

    constructor(IEntryPoint _entryPoint, IKintoID _kintoID) {
        accountImplementation = new KintoWallet(_entryPoint, _kintoID);
        kintoID = _kintoID;
        factoryOwner = msg.sender;
    }

    function upgradeImplementation(KintoWallet newImplementationWallet) public {
        require(msg.sender == factoryOwner, 'only owner');
        accountImplementation = newImplementationWallet;
    }

    /**
     * create an account, and return its address.
     * returns the address even if the account is already deployed.
     * Note that during UserOperation execution, this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress() would work even after account creation
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
        require(kintoID.isKYC(owner), 'KYC required');
    }

    /**
     * calculate the counterfactual address of this account as it would be returned by createAccount()
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

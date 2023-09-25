// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import '@openzeppelin/contracts/utils/Create2.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import { UpgradeableBeacon } from '@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol';
import { SafeBeaconProxy } from '../proxy/SafeBeaconProxy.sol';

import '../interfaces/IKintoID.sol';
import '../interfaces/IKintoWalletFactory.sol';
import './KintoWallet.sol';

/**
 * @title KintoWalletFactory
 * @dev A kinto wallet factory contract for KintoWallet
 *   Sits behind a proxy. It's upgradeable.
 *   A UserOperations "initCode" holds the address of the factory,
 *   and a method call (to createAccount, in this sample factory).
 *   The factory's createAccount returns the target account address even if it is already installed.
 *   This way, the entryPoint.getSenderAddress() can be called either
 *   before or after the account is created.
 */
contract KintoWalletFactory is Initializable, UUPSUpgradeable, IKintoWalletFactory {

    /* ============ State Variables ============ */
    address immutable public override factoryOwner;
    UpgradeableBeacon private immutable _beacon;

    IKintoID public override kintoID;
    mapping (address => uint256) public override walletVersion;
    uint256 public override factoryWalletVersion;
    uint256 public override totalWallets;

    /* ============ Events ============ */
    event KintoWalletFactoryCreation(address indexed account, address indexed owner, uint version);
    event KintoWalletFactoryUpgraded(address indexed oldImplementation,
        address indexed newImplementation);

    /* ============ Constructor ============ */
    constructor(UpgradeableBeacon _beaconp) {
        factoryOwner = msg.sender;
        _beacon = _beaconp;
        _disableInitializers();
    }

    /**
     * @dev Upgrade calling `upgradeTo()`
     */
    function initialize(
        IKintoID _kintoID
    ) external virtual initializer {
        __UUPSUpgradeable_init();
        factoryWalletVersion = 1;
        kintoID = _kintoID;
    }

    /**
     * @dev Upgrade the wallet implementations using the beacon
     * @param newImplementationWallet The new implementation
     */
    function upgradeAllWalletImplementations(
        IKintoWallet newImplementationWallet
    ) external override {
        require(msg.sender == factoryOwner, 'only owner');
        require(address(newImplementationWallet) != address(0), 'invalid address');
        factoryWalletVersion++;
        emit KintoWalletFactoryUpgraded(address(newImplementationWallet),
            address(newImplementationWallet));
        _beacon.upgradeTo(address(newImplementationWallet));
    }

    /**
     *
     * @dev Create an account, and return its address.
     * It returns the address even if the account is already deployed.
     * Note that during UserOperation execution,
     * this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress()
     * would work even after account creation
     * @param owner The owner address
     * @param salt The salt to use for the calculation
     * @return ret address of the account
     */
    function createAccount(address owner, uint256 salt) external override returns (
        IKintoWallet ret
    ) {
        require(kintoID.isKYC(owner), 'KYC required');
        address addr = getAddress(owner, salt);
        uint codeSize = addr.code.length;
        if (codeSize > 0) {
            return KintoWallet(payable(addr));
        }
        // ret = KintoWallet(payable(new ERC1967Proxy{salt : bytes32(salt)}(
        //         address(accountImplementation),
        //         abi.encodeCall(KintoWallet.initialize, (owner))
        //     )));

        ret = KintoWallet(payable(
            new SafeBeaconProxy{salt : bytes32(salt)}(
                    address(_beacon),
                    abi.encodeWithSelector(
                        KintoWallet.initialize.selector,
                        owner
                    )
                )
        ));

        walletVersion[address(ret)] = factoryWalletVersion;
        totalWallets++;
        // Emit event
        emit KintoWalletFactoryCreation(address(ret), owner, factoryWalletVersion);
    }

    /* ============ Deploy Custom Contract ============ */

    /**
     * @dev Deploys a contract using `CREATE2`. The address where the contract
     * will be deployed can be known in advance via {computeAddress}.
     *
     * The bytecode for a contract can be obtained from Solidity with
     * `type(contractName).creationCode`.
     *
     * Requirements:
     * -  sender myst be KYC'd
     * - `bytecode` must not be empty.
     * - `salt` must have not been used for `bytecode` already.
     * - the factory must have a balance of at least `amount`.
     * - if `amount` is non-zero, `bytecode` must have a `payable` constructor.
     */
    function deployContract(
        uint amount,
        bytes memory bytecode,
        bytes32 salt
    ) external override returns (address) {
        require(kintoID.isKYC(msg.sender), 'KYC required');
        return Create2.deploy(amount, salt, bytecode);
    }

    /* ============ Recovery Functions ============ */

    /**
     * @dev Start the account recovery process
     * @param _account The wallet account address
     * After successful KYC again, the user can request to recover the account
     */
    function startAccountRecovery(address _account) external override {
        require(msg.sender == factoryOwner, 'only owner');
        require(walletVersion[_account] > 0, 'Not a valid account');
        KintoWallet(payable(_account)).startRecovery();
    }

   /**
     * @dev Finish the account recovery process
     * @param _account The wallet account address
     * @param _newOwner The new owner address (has to be KYC'd)
     * After the recovery time has finished, the user can set a new owner on the account
     * Old owner NFT has to be burned to prevent duplicate NFTs
     */
    function finishAccountRecovery(address _account, address _newOwner) external override {
        require(msg.sender == factoryOwner, 'only owner');
        require(walletVersion[_account] > 0, 'Not a valid account');
        require(!kintoID.isKYC(KintoWallet(payable(_account)).owners(0)), 'Old KYC must be burned');
        require(kintoID.isKYC(_newOwner), 'New KYC must be minted');
        address[] memory newSigners = new address[](1);
        newSigners[0] = _newOwner;
        KintoWallet(payable(_account)).finishRecovery(newSigners);
    }

    /* ============ View Functions ============ */

    /**
     * @dev Gets the version of a current wallet
     * @param wallet The wallet address
     * @return The version of the wallet. 0 if it is not a wallet
     */
    function getWalletVersion(address wallet) external view override returns (uint256) {
        return walletVersion[wallet];
    }

    /**
     * @dev Calculates the counterfactual address of this account
     * as it would be returned by createAccount()
     * @param owner The owner address
     * @param salt The salt to use for the calculation
     * @return The address of the account
     */
    function getAddress(address owner, uint256 salt) public view override returns (address) {
        return Create2.computeAddress(bytes32(salt), keccak256(abi.encodePacked(
                type(SafeBeaconProxy).creationCode,
                abi.encode(
                    address(_beacon),
                    abi.encodeCall(KintoWallet.initialize, (owner))
                )
            )));
    }

    /**
     * @dev Calculates the counterfactual address of this contract as it
     * would be returned by deployContract()
     * @param salt Salt used by CREATE2
     * @param byteCodeHash The bytecode hash (keccack256) of the contract to deploy
     * @return address of the contract to deploy
     */
    function getContractAddress(
        bytes32 salt,
        bytes32 byteCodeHash
    ) public view override returns (address) {
        return Create2.computeAddress(salt, byteCodeHash, address(this));
    }

    /**
     * @dev Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the factory is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override {
        (newImplementation);
        require(msg.sender == factoryOwner, 'only owner');
    }
}

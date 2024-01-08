// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {SafeBeaconProxy} from "../proxy/SafeBeaconProxy.sol";

import "../interfaces/IKintoID.sol";
import "../interfaces/IKintoWalletFactory.sol";
import "./KintoWallet.sol";

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
contract KintoWalletFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable, IKintoWalletFactory {
    /* ============ State Variables ============ */
    UpgradeableBeacon public beacon;
    KintoWallet private immutable _implAddress;
    IKintoID public override kintoID;
    mapping(address => uint256) public override walletTs;
    uint256 public override factoryWalletVersion;
    uint256 public override totalWallets;

    /* ============ Events ============ */
    event KintoWalletFactoryCreation(address indexed account, address indexed owner, uint256 version);
    event KintoWalletFactoryUpgraded(address indexed oldImplementation, address indexed newImplementation);

    /* ============ Constructor & Upgrades ============ */
    constructor(KintoWallet _implAddressP) {
        _disableInitializers();
        _implAddress = _implAddressP;
    }

    /**
     * @dev Upgrade calling `upgradeTo()`
     */
    function initialize(IKintoID _kintoID) external virtual initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        beacon = new UpgradeableBeacon(address(_implAddress));
        factoryWalletVersion = 1;
        kintoID = _kintoID;
    }

    /**
     * @dev Upgrade the wallet implementations using the beacon
     * @param newImplementationWallet The new implementation
     */
    function upgradeAllWalletImplementations(IKintoWallet newImplementationWallet) external override onlyOwner {
        require(
            address(newImplementationWallet) != address(0)
                && address(newImplementationWallet) != beacon.implementation(),
            "invalid address"
        );
        factoryWalletVersion++;
        emit KintoWalletFactoryUpgraded(beacon.implementation(), address(newImplementationWallet));
        beacon.upgradeTo(address(newImplementationWallet));
    }

    /**
     * @dev Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the factory is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        (newImplementation);
    }

    /* ============ Create Wallet ============ */

    /**
     *
     * @dev Create an account, and return its address.
     * It returns the address even if the account is already deployed.
     * Note that during UserOperation execution,
     * this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress()
     * would work even after account creation
     * @param owner The owner address
     * @param recoverer The recoverer address
     * @param salt The salt to use for the calculation
     * @return ret address of the account
     */
    function createAccount(address owner, address recoverer, uint256 salt)
        external
        override
        returns (IKintoWallet ret)
    {
        require(kintoID.isKYC(owner), "KYC required");
        address addr = getAddress(owner, recoverer, salt);
        uint256 codeSize = addr.code.length;

        if (codeSize > 0) {
            return KintoWallet(payable(addr));
        }

        ret = KintoWallet(
            payable(
                new SafeBeaconProxy{salt: bytes32(salt)}(
                    address(beacon), abi.encodeCall(KintoWallet.initialize, (owner, recoverer))
                )
            )
        );

        walletTs[address(ret)] = block.timestamp;
        totalWallets++;
        // Emit event
        emit KintoWalletFactoryCreation(address(ret), owner, factoryWalletVersion);
    }

    /* ============ Modify Wallet ============ */

    /**
     * @dev Starts wallet recovery process. Only the wallet recoverer can do it.
     * @param wallet The wallet address
     */
    function startWalletRecovery(address payable wallet) external override {
        require(walletTs[wallet] > 0, "invalid wallet");
        require(msg.sender == KintoWallet(wallet).recoverer(), "only recoverer");
        KintoWallet(wallet).startRecovery();
    }

    /**
     * @dev Completes wallet recovery process. Only the wallet recoverer can do it.
     * @param wallet The wallet address
     * @param newSigners new signers array
     */
    function completeWalletRecovery(address payable wallet, address[] calldata newSigners) external override {
        require(walletTs[wallet] > 0, "invalid wallet");
        require(msg.sender == KintoWallet(wallet).recoverer(), "only recoverer");
        KintoWallet(wallet).finishRecovery(newSigners);
    }

    function changeWalletRecoverer(address payable wallet, address _newRecoverer) external override {
        require(walletTs[wallet] > 0, "invalid wallet");
        require(msg.sender == KintoWallet(wallet).recoverer(), "only recoverer");
        KintoWallet(wallet).changeRecoverer(_newRecoverer);
    }
    /* ============ Deploy Custom Contract ============ */

    /**
     * @dev Deploys a contract using `CREATE2`. The address where the contract
     * will be deployed can be known in advance via {computeAddress}.
     *
     * This can be called directly by a developer for ease of use.
     * The bytecode for a contract can be obtained from Solidity with
     * `type(contractName).creationCode`.
     *
     * Requirements:
     * -  sender myst be KYC'd
     * - `bytecode` must not be empty.
     * - `salt` must have not been used for `bytecode` already.
     * - the factory must have a balance of at least `amount`.
     * - if `amount` is non-zero, `bytecode` must have a `payable` constructor.
     * @param contractOwner The address to be set as owner
     * @param amount The amount of wei to send with the contract creation
     * @param bytecode The bytecode of the contract to deploy
     * @param salt The salt to use for the calculation
     */
    function deployContract(address contractOwner, uint256 amount, bytes calldata bytecode, bytes32 salt)
        external
        payable
        override
        returns (address)
    {
        require(kintoID.isKYC(msg.sender), "KYC required");
        return _deployAndAssignOwnership(contractOwner, amount, bytecode, salt);
    }

    /**
     * @dev Fund a wallet through the factory given chain restrictions
     * @param wallet The wallet address to send eth to
     */
    function fundWallet(address payable wallet) external payable override {
        require(
            msg.value > 0 && walletTs[wallet] > 0 && kintoID.isKYC(KintoWallet(wallet).owners(0))
                && KintoWallet(payable(wallet)).isFunderWhitelisted(msg.sender),
            "Invalid wallet or funder"
        );
        wallet.transfer(msg.value);
    }

    /* ============ View Functions ============ */

    /**
     * @dev Gets the creation timestamp of a current wallet
     * @param wallet The wallet address
     * @return The timestamp of the wallet. 0 if it is not a wallet
     */
    function getWalletTimestamp(address wallet) external view override returns (uint256) {
        return walletTs[wallet];
    }

    /**
     * @dev Calculates the counterfactual address of this account
     * as it would be returned by createAccount()
     * @param owner The owner address
     * @param recoverer The address that can recover the account in an emergency
     * @param salt The salt to use for the calculation
     * @return The address of the account
     */
    function getAddress(address owner, address recoverer, uint256 salt) public view override returns (address) {
        return Create2.computeAddress(
            bytes32(salt),
            keccak256(
                abi.encodePacked(
                    type(SafeBeaconProxy).creationCode,
                    abi.encode(address(beacon), abi.encodeCall(KintoWallet.initialize, (owner, recoverer)))
                )
            )
        );
    }

    /**
     * @dev Calculates the counterfactual address of this contract as it
     * would be returned by deployContract()
     * @param salt Salt used by CREATE2
     * @param byteCodeHash The bytecode hash (keccack256) of the contract to deploy
     * @return address of the contract to deploy
     */
    function getContractAddress(bytes32 salt, bytes32 byteCodeHash) external view override returns (address) {
        return Create2.computeAddress(salt, byteCodeHash, address(this));
    }

    /* ============ Internal Functions ============ */

    function _preventCreationBytecode(bytes calldata _bytes) internal view {
        // Prevent direct deployment of KintoWallet contracts
        bytes memory walletInitCode = type(SafeBeaconProxy).creationCode;
        if (_bytes.length > walletInitCode.length + 32) {
            // Make sure this beacon cannot be called with creation code
            uint256 offset = 12 + walletInitCode.length;
            address beaconAddress = address(0);
            bytes memory slice = _bytes[offset:offset + 20];
            assembly {
                beaconAddress := mload(add(slice, 20))
            }
            // Compare the extracted beacon address with the disallowed address
            require(beaconAddress != address(beacon), "Direct KintoWallet deployment not allowed");
        }
    }

    function _deployAndAssignOwnership(address newOwner, uint256 amount, bytes calldata bytecode, bytes32 salt)
        internal
        returns (address)
    {
        require(amount == msg.value, "amount mismatch");
        _preventCreationBytecode(bytecode);
        address created = Create2.deploy(amount, salt, bytecode);
        // Assign ownership to the deployer if needed
        try OwnableUpgradeable(created).owner() returns (address owner) {
            if (owner == address(this)) {
                OwnableUpgradeable(created).transferOwnership(newOwner);
            }
        } catch {}
        return created;
    }
}

contract KintoWalletFactoryV2 is KintoWalletFactory {
    constructor(KintoWallet _implAddressP) KintoWalletFactory(_implAddressP) {}
}

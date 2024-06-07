// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {SafeBeaconProxy} from "../proxy/SafeBeaconProxy.sol";

import "../interfaces/IKintoID.sol";
import "../interfaces/bridger/IBridgerL2.sol";
import "../interfaces/IFaucet.sol";
import "../interfaces/IKintoWalletFactory.sol";
import "../interfaces/IKintoWallet.sol";

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
    IKintoWallet private immutable _implAddress;
    IKintoID public override kintoID;
    mapping(address => uint256) public override walletTs; // wallet address => timestamp
    uint256 public override factoryWalletVersion;
    uint256 public override totalWallets;
    mapping(address => bool) public override adminApproved;

    /* ============ Events ============ */

    event KintoWalletFactoryCreation(address indexed account, address indexed owner, uint256 version);
    event KintoWalletFactoryUpgraded(address indexed oldImplementation, address indexed newImplementation);

    /* ============ Constructor & Upgrades ============ */

    constructor(IKintoWallet _implAddressP) {
        _disableInitializers();
        _implAddress = _implAddressP;
    }

    /* ============ External/Public methods ============ */

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
        if (
            address(newImplementationWallet) == address(0)
                || address(newImplementationWallet) == beacon.implementation()
        ) revert InvalidImplementation();
        factoryWalletVersion++;
        emit KintoWalletFactoryUpgraded(beacon.implementation(), address(newImplementationWallet));
        beacon.upgradeTo(address(newImplementationWallet));
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
     * @param recoverer The recoverer address
     * @param salt The salt to use for the calculation
     * @return ret address of the account
     */
    function createAccount(address owner, address recoverer, bytes32 salt)
        external
        override
        returns (IKintoWallet ret)
    {
        if (owner == address(0) || recoverer == address(0)) revert InvalidInput();
        if (!kintoID.isKYC(owner) || owner != msg.sender) revert KYCRequired();
        address addr = getAddress(owner, recoverer, salt);
        uint256 codeSize = addr.code.length;

        if (codeSize > 0) {
            return IKintoWallet(payable(addr));
        }

        ret = IKintoWallet(
            payable(
                new SafeBeaconProxy{salt: salt}(
                    address(beacon), abi.encodeCall(IKintoWallet.initialize, (owner, recoverer))
                )
            )
        );

        walletTs[address(ret)] = block.timestamp;
        totalWallets++;

        emit KintoWalletFactoryCreation(address(ret), owner, factoryWalletVersion);
    }

    /**
     * @dev Starts wallet recovery process. Only the wallet recoverer can do it.
     * @param wallet The wallet address
     */
    function startWalletRecovery(address payable wallet) external override {
        if (walletTs[wallet] == 0) revert InvalidWallet();
        if (msg.sender != IKintoWallet(wallet).recoverer()) revert OnlyRecoverer();
        IKintoWallet(wallet).startRecovery();
    }

    /**
     * @dev Completes wallet recovery process. Only the wallet recoverer can do it.
     * @param wallet The wallet address
     * @param newSigners new signers array
     */
    function completeWalletRecovery(address payable wallet, address[] calldata newSigners) external override {
        if (walletTs[wallet] == 0) revert InvalidWallet();
        if (msg.sender != IKintoWallet(wallet).recoverer()) revert OnlyRecoverer();
        if (!adminApproved[wallet]) revert NotAdminApproved();
        // Transfer kinto id from old to new signer
        if (!kintoID.isKYC(newSigners[0]) && kintoID.isKYC(IKintoWallet(wallet).owners(0))) {
            kintoID.transferOnRecovery(IKintoWallet(wallet).owners(0), newSigners[0]);
        }
        // Set new signers and policy
        IKintoWallet(wallet).completeRecovery(newSigners);
        // Resets approved wallet
        adminApproved[wallet] = false;
    }

    /**
     * @dev Approve wallet recovery. Only the owner can do it.
     * @param wallet The wallet address that can be recovered
     */
    function approveWalletRecovery(address wallet) external override onlyOwner {
        adminApproved[wallet] = true;
    }

    /**
     * @dev Change wallet recoverer. Only the wallet recoverer can do it.
     * @param wallet The wallet address
     * @param _newRecoverer The new recoverer address
     */
    function changeWalletRecoverer(address payable wallet, address _newRecoverer) external override {
        if (walletTs[wallet] == 0) revert InvalidWallet();
        if (msg.sender != IKintoWallet(wallet).recoverer()) revert OnlyRecoverer();
        IKintoWallet(wallet).changeRecoverer(_newRecoverer);
    }

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
        if (!kintoID.isKYC(msg.sender)) revert KYCRequired();
        return _deployAndAssignOwnership(contractOwner, amount, bytecode, salt);
    }

    /**
     * @dev Fund a wallet through the factory given chain restrictions
     * @param wallet The wallet address to send eth to
     */
    function fundWallet(address payable wallet) external payable override {
        if (
            msg.value == 0 || walletTs[wallet] == 0 || !kintoID.isKYC(IKintoWallet(wallet).owners(0))
                || !IKintoWallet(payable(wallet)).isFunderWhitelisted(msg.sender)
        ) revert InvalidWalletOrFunder();
        (bool sent,) = wallet.call{value: msg.value}("");
        if (!sent) revert SendFailed();
    }

    /**
     * @dev Claim from a faucet on behalf of a user
     * @param _faucet The faucet address
     * @param _signatureData The signature data
     */
    function claimFromFaucet(address _faucet, IFaucet.SignatureData calldata _signatureData) external override {
        if (!IAccessControl(address(kintoID)).hasRole(kintoID.KYC_PROVIDER_ROLE(), msg.sender)) revert InvalidSender();
        if (address(_faucet) == address(0)) revert InvalidFaucet();
        IFaucet(_faucet).claimKintoETH(_signatureData);
    }

    /**
     * @dev Sets the deposit on the L2 to be claimed by the wallet at the end of phase IV
     * Note: Only owner can call this function
     * @param walletAddress address of the wallet
     * @param assetL2 address of the asset on the L2
     * @param amount amount of the asset to receive
     */
    function writeL2Deposit(address walletAddress, address assetL2, uint256 amount) external override {
        if (msg.sender != 0xb539019776eF803E89EC062Ad54cA24D1Fdb008a) {
            revert InvalidSender();
        }
        IBridgerL2(0x26181Dfc530d96523350e895180b09BAf3d816a0).writeL2Deposit(walletAddress, assetL2, amount);
    }

    /**
     * @dev Send money to an account from privileged accounts or from kyc accounts to kyc accounts or contracts.
     * @param target The target address
     */
    function sendMoneyToAccount(address target) external payable override {
        if (target == address(0)) revert InvalidTarget();
        bool isPrivileged =
            owner() == msg.sender || IAccessControl(address(kintoID)).hasRole(kintoID.KYC_PROVIDER_ROLE(), msg.sender);
        if (!isPrivileged && !kintoID.isKYC(msg.sender)) revert OnlyPrivileged();
        bool isValidTarget = kintoID.isKYC(target) || target.code.length > 0
            || IAccessControl(address(kintoID)).hasRole(kintoID.KYC_PROVIDER_ROLE(), target);
        if (!isValidTarget && !isPrivileged) revert InvalidTarget();
        (bool sent,) = target.call{value: msg.value}("");
        if (!sent) revert SendFailed();
    }

    /**
     * @dev Send money to a recoverer from a wallet to do the recovery process
     * @param wallet The wallet address
     * @param recoverer The recoverer address
     */
    function sendMoneyToRecoverer(address wallet, address recoverer) external payable override {
        if (recoverer.balance > 0) revert InvalidRecoverer();
        if (walletTs[wallet] == 0) revert InvalidWallet();
        if (recoverer != IKintoWallet(wallet).recoverer()) revert OnlyRecoverer();
        bool isPrivileged =
            owner() == msg.sender || IAccessControl(address(kintoID)).hasRole(kintoID.KYC_PROVIDER_ROLE(), msg.sender);
        if (!isPrivileged) revert OnlyRecoverer();
        (bool sent,) = recoverer.call{value: msg.value}("");
        if (!sent) revert SendFailed();
    }

    /* ============ Getters ============ */

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
    function getAddress(address owner, address recoverer, bytes32 salt) public view override returns (address) {
        return Create2.computeAddress(
            bytes32(salt),
            keccak256(
                abi.encodePacked(
                    type(SafeBeaconProxy).creationCode,
                    abi.encode(address(beacon), abi.encodeCall(IKintoWallet.initialize, (owner, recoverer)))
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

    /* ============ Internal methods ============ */

    /**
     * @notice Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     * @dev This function is called by the proxy contract when the factory is upgraded
     */
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        (newImplementation);
    }

    function _preventWalletDeployment(bytes calldata _bytecode) internal view {
        bytes memory walletInitCode = type(SafeBeaconProxy).creationCode;
        if (_bytecode.length > walletInitCode.length + 32) {
            uint256 offset = 12 + walletInitCode.length;

            // extract beacon address directly from calldata
            address beaconAddress;
            bytes memory slice = _bytecode[offset:offset + 20];
            assembly {
                beaconAddress := mload(add(slice, 20))
            }

            if (beaconAddress == address(beacon)) {
                revert DeploymentNotAllowed("Direct KintoWallet deployment not allowed");
            }
        }
    }

    function _deployAndAssignOwnership(address newOwner, uint256 amount, bytes calldata bytecode, bytes32 salt)
        internal
        returns (address)
    {
        if (amount != msg.value) revert AmountMismatch();
        if (bytecode.length == 0) revert EmptyBytecode();
        _preventWalletDeployment(bytecode);

        // deploy the contract using `CREATE2`
        address created = Create2.deploy(amount, salt, bytecode);

        // assign ownership to newOwner if the contract is Ownable
        try OwnableUpgradeable(created).owner() returns (address owner) {
            if (owner == address(this)) {
                OwnableUpgradeable(created).transferOwnership(newOwner);
            }
        } catch {}
        return created;
    }
}

contract KintoWalletFactoryV16 is KintoWalletFactory {
    constructor(IKintoWallet _implAddressP) KintoWalletFactory(_implAddressP) {}
}

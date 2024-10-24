// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";
import {SafeBeaconProxy} from "@kinto-core/proxy/SafeBeaconProxy.sol";

import "@kinto-core/interfaces/IKintoID.sol";
import "@kinto-core/interfaces/bridger/IBridgerL2.sol";
import "@kinto-core/interfaces/IFaucet.sol";
import "@kinto-core/interfaces/IKintoWalletFactory.sol";
import "@kinto-core/interfaces/IKintoWallet.sol";
import "@kinto-core/interfaces/IKintoAppRegistry.sol";

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
    /* ============ Constants & Immutables ============ */

    /// @notice DEPRECATED: Address of an initial wallet implementation.
    IKintoWallet private immutable _implAddress;
    IKintoID public immutable override kintoID;
    IKintoAppRegistry public immutable override appRegistry;
    RewardsDistributor public immutable override rewardsDistributor;

    /* ============ State Variables ============ */

    UpgradeableBeacon public beacon;
    /// @notice DEPRECATED: Address of an KintoId.
    IKintoID private __kintoID;
    mapping(address => uint256) public override walletTs; // wallet address => timestamp
    uint256 public override factoryWalletVersion;
    uint256 public override totalWallets;
    mapping(address => bool) public override adminApproved;
    /// @notice DEPRECATED: Address of an AppRegistry.
    IKintoAppRegistry private __appRegistry;

    /* ============ Events ============ */

    event KintoWalletFactoryCreation(address indexed account, address indexed owner, uint256 version);
    event KintoWalletFactoryUpgraded(address indexed oldImplementation, address indexed newImplementation);

    /* ============ Constructor & Upgrades ============ */

    constructor(
        IKintoWallet _implAddressP,
        IKintoAppRegistry _appRegistry,
        IKintoID _kintoID,
        RewardsDistributor _rewardsDistributor
    ) {
        _disableInitializers();

        _implAddress = _implAddressP;
        appRegistry = _appRegistry;
        kintoID = _kintoID;
        rewardsDistributor = _rewardsDistributor;
    }

    /* ============ External/Public methods ============ */

    /**
     * @dev Upgrade calling `upgradeTo()`
     */
    function initialize() external virtual initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        beacon = new UpgradeableBeacon(address(_implAddress));
        factoryWalletVersion = 1;
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

        if (addr.code.length > 0) {
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
        // Claim new user rewards
        rewardsDistributor.newUserClaim(address(ret));
        emit KintoWalletFactoryCreation(address(ret), owner, factoryWalletVersion);
    }

    /**
     * @dev Starts wallet recovery process. Only the wallet recoverer can do it.
     * @param wallet The wallet address
     */
    function startWalletRecovery(address payable wallet) external override {
        if (walletTs[wallet] == 0) revert InvalidWallet(wallet);
        if (msg.sender != IKintoWallet(wallet).recoverer()) {
            revert OnlyRecoverer(msg.sender, IKintoWallet(wallet).recoverer());
        }
        IKintoWallet(wallet).startRecovery();
    }

    /**
     * @dev Completes wallet recovery process. Only the wallet recoverer can do it.
     * @param wallet The wallet address
     * @param newSigners new signers array
     */
    function completeWalletRecovery(address payable wallet, address[] calldata newSigners) external override {
        if (walletTs[wallet] == 0) revert InvalidWallet(wallet);
        if (msg.sender != IKintoWallet(wallet).recoverer()) {
            revert OnlyRecoverer(msg.sender, IKintoWallet(wallet).recoverer());
        }
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
        if (walletTs[wallet] == 0) revert InvalidWallet(wallet);
        if (msg.sender != IKintoWallet(wallet).recoverer()) {
            revert OnlyRecoverer(msg.sender, IKintoWallet(wallet).recoverer());
        }
        IKintoWallet(wallet).changeRecoverer(_newRecoverer);
    }

    /**
     * @dev Fund a wallet through the factory given chain restrictions
     * @param wallet The wallet address to send eth to
     */
    function fundWallet(address payable wallet) external payable override {
        if (
            msg.value == 0 || walletTs[wallet] == 0 || !kintoID.isKYC(IKintoWallet(wallet).owners(0))
                || !IKintoWallet(payable(wallet)).isFunderWhitelisted(msg.sender)
        ) revert InvalidWalletOrFunder(wallet);
        (bool sent,) = wallet.call{value: msg.value}("");
        if (!sent) revert SendFailed();
    }

    /**
     * @dev Claim from a faucet on behalf of a user
     * @param _faucet The faucet address
     * @param _signatureData The signature data
     */
    function claimFromFaucet(address _faucet, IFaucet.SignatureData calldata _signatureData) external override {
        if (!IAccessControl(address(kintoID)).hasRole(kintoID.KYC_PROVIDER_ROLE(), msg.sender)) {
            revert InvalidSender(msg.sender);
        }
        if (address(_faucet) == address(0)) revert InvalidTarget(_faucet);
        IFaucet(_faucet).claimKintoETH(_signatureData);
    }

    /**
     * @dev Send money to an account from privileged accounts or from kyc accounts to kyc accounts or contracts.
     * @param target The target address
     */
    function sendMoneyToAccount(address target) external payable override {
        if (target == address(0)) revert InvalidTarget(target);
        bool isPrivileged =
            owner() == msg.sender || IAccessControl(address(kintoID)).hasRole(kintoID.KYC_PROVIDER_ROLE(), msg.sender);
        if (!isPrivileged && !kintoID.isKYC(msg.sender)) revert OnlyPrivileged(msg.sender);
        bool isValidTarget = kintoID.isKYC(target) || target.code.length > 0
            || IAccessControl(address(kintoID)).hasRole(kintoID.KYC_PROVIDER_ROLE(), target);
        if (!isValidTarget && !isPrivileged) revert InvalidTarget(target);
        (bool sent,) = target.call{value: msg.value}("");
        if (!sent) revert SendFailed();
    }

    /**
     * @dev Send money to a recoverer from a wallet to do the recovery process
     * @param wallet The wallet address
     * @param recoverer The recoverer address
     */
    function sendMoneyToRecoverer(address wallet, address recoverer) external payable override {
        if (walletTs[wallet] == 0) revert InvalidWallet(wallet);
        if (recoverer != IKintoWallet(wallet).recoverer()) {
            revert OnlyRecoverer(recoverer, IKintoWallet(wallet).recoverer());
        }
        (bool sent,) = recoverer.call{value: msg.value}("");
        if (!sent) revert SendFailed();
    }

    /**
     * @dev Send eth to the deployer of a wallet
     * @param deployer The deployer address
     */
    function sendETHToDeployer(address deployer) external payable override {
        if (walletTs[msg.sender] == 0) revert InvalidWallet(msg.sender);
        if (deployer == address(0)) revert InvalidTarget(deployer);
        if (appRegistry.deployerToWallet(deployer) != msg.sender) revert InvalidWallet(deployer);
        (bool sent,) = deployer.call{value: msg.value}("");
        if (!sent) revert SendFailed();
    }

    /**
     * @dev Send eth to the EOA of an app
     * @param eoa The EOA address
     * @param app The app address
     */
    function sendETHToEOA(address eoa, address app) external payable override {
        if (walletTs[msg.sender] == 0) revert InvalidWallet(msg.sender);
        if (eoa == address(0) || app == address(0)) revert InvalidTarget(address(0));
        if (appRegistry.devEoaToApp(eoa) != app) revert InvalidTarget(app);
        if (IERC721Enumerable(address(appRegistry)).ownerOf(appRegistry.getAppMetadata(app).tokenId) != msg.sender) {
            revert InvalidWallet(msg.sender);
        }
        (bool sent,) = eoa.call{value: msg.value}("");
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

    /* ============ Internal methods ============ */

    /**
     * @notice Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     * @dev This function is called by the proxy contract when the factory is upgraded
     */
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        (newImplementation);
    }
}

contract KintoWalletFactoryV23 is KintoWalletFactory {
    constructor(
        IKintoWallet _implAddressP,
        IKintoAppRegistry _appRegistry,
        IKintoID _kintoID,
        RewardsDistributor _rewardsDistributor
    ) KintoWalletFactory(_implAddressP, _appRegistry, _kintoID, _rewardsDistributor) {}
}

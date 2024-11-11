// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {UUPSUpgradeable as UUPSUpgradeable5} from
    "@openzeppelin-5.0.1/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {EntryPoint} from "@aa/core/EntryPoint.sol";
import {KintoID} from "@kinto-core/KintoID.sol";

import "@kinto-core/wallet/KintoWalletFactory.sol";
import "@kinto-core/paymasters/SponsorPaymaster.sol";
import "@kinto-core/apps/KintoAppRegistry.sol";

import "@kinto-core/interfaces/ISponsorPaymaster.sol";
import "@kinto-core/interfaces/IKintoWallet.sol";
import {KintoWallet} from "@kinto-core/wallet/KintoWallet.sol";
import {BridgedToken} from "@kinto-core/tokens/bridged/BridgedToken.sol";

import {Create2Helper} from "@kinto-core-test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "@kinto-core-test/helpers/ArtifactsReader.sol";
import {UserOp} from "@kinto-core-test/helpers/UserOp.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {DeployerHelper} from "@kinto-core-script/utils/DeployerHelper.sol";
import {SignatureHelper} from "@kinto-core-test/helpers/SignatureHelper.sol";

import {Constants} from "@kinto-core-script/migrations/const.sol";
import {SaltHelper} from "@kinto-core-script/utils/SaltHelper.sol";

import "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

interface IInitialize {
    function initialize() external;
}

contract MigrationHelper is Script, DeployerHelper, SignatureHelper, UserOp, SaltHelper, Constants {
    using ECDSAUpgradeable for bytes32;
    using stdJson for string;

    uint256 internal deployerPrivateKey;
    address internal deployer;
    address internal kintoAdminWallet;
    uint256 internal hardwareWalletType;
    KintoWalletFactory internal factory;
    EntryPoint internal entryPoint;
    SponsorPaymaster internal paymaster;
    KintoID internal kintoID;

    function run() public virtual {
        console2.log("Running on chain with id:", vm.toString(block.chainid));
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        try vm.envUint("HARDWARE_WALLET_TYPE") returns (uint256 hwType) {
            hardwareWalletType = hwType;
        } catch {}
        deployer = vm.addr(deployerPrivateKey);
        console2.log("Deployer:", deployer);

        kintoAdminWallet = _getChainDeployment("KintoWallet-admin");
        factory = KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));
        entryPoint = EntryPoint(payable(_getChainDeployment("EntryPoint")));
        paymaster = SponsorPaymaster(payable(_getChainDeployment("SponsorPaymaster")));
        kintoID = KintoID(payable(_getChainDeployment("KintoID")));
    }

    /// @dev deploys proxy contract via factory from deployer address
    function _deployProxy(string memory contractName, address implementation, bytes32 salt)
        internal
        returns (address proxy)
    {
        // deploy Proxy contract
        vm.broadcast(deployerPrivateKey);
        proxy = address(new UUPSProxy{salt: salt}(address(implementation), ""));

        console2.log(string.concat(contractName, ": ", vm.toString(address(proxy))));
    }

    function _deployProxy(string memory contractName, address implementation) internal returns (address proxy) {
        return _deployProxy(contractName, implementation, bytes32(0));
    }

    /// @dev deploys implementation contracts via entrypoint from deployer address
    /// @dev if contract is ownable, it will transfer ownership to msg.sender
    function _deployImplementation(
        string memory contractName,
        string memory version,
        bytes memory bytecode,
        bytes32 salt
    ) internal returns (address impl) {
        // deploy new implementation via factory
        vm.broadcast(deployerPrivateKey);
        impl = create2(bytecode, salt);

        console2.log(string.concat(contractName, version, "-impl: ", vm.toString(address(impl))));
    }

    function _deployImplementation(string memory contractName, string memory version, bytes memory bytecode)
        internal
        returns (address impl)
    {
        return _deployImplementation(contractName, version, bytecode, bytes32(0));
    }

    function _deployImplementationAndUpgrade(string memory contractName, string memory version, bytes memory bytecode)
        internal
        returns (address impl)
    {
        return _deployImplementationAndUpgrade(contractName, version, bytecode, bytes32(0));
    }

    /// @notice deploys implementation contracts via factory from deployer address and upgrades them
    /// @dev if contract is KintoWallet we call upgradeAllWalletImplementations
    /// @dev if contract is allowed to receive EOA calls, we call upgradeTo directly. Otherwise, we use EntryPoint to upgrade
    function _deployImplementationAndUpgrade(
        string memory contractName,
        string memory version,
        bytes memory bytecode,
        bytes32 salt
    ) internal returns (address impl) {
        bool isWallet = keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked("KintoWallet"));
        address proxy = _getChainDeployment(contractName);

        if (!isWallet) require(proxy != address(0), "Need to execute main deploy script first");

        // (1). deploy new implementation via wallet factory
        impl = _deployImplementation(contractName, version, bytecode, salt);
        // (2). call upgradeTo to set new implementation
        if (isWallet) {
            _upgradeWallet(impl);
        } else {
            try Ownable(proxy).owner() returns (address owner) {
                if (owner != kintoAdminWallet && owner != address(0)) {
                    console2.log(
                        "%s contract is not owned by the KintoWallet-admin, its owner is %s",
                        contractName,
                        vm.toString(owner)
                    );
                    revert("Contract is not owned by KintoWallet-admin");
                }
                _upgradeTo(proxy, impl, deployerPrivateKey);
            } catch {
                _upgradeTo(proxy, impl, deployerPrivateKey);
            }
        }
    }

    function _upgradeWallet(address impl) internal {
        address payable from = payable(kintoAdminWallet);
        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = hardwareWalletType;

        // address oldImpl = factory.beacon().implementation();

        bytes memory data = abi.encodeWithSelector(KintoWalletFactory.upgradeAllWalletImplementations.selector, impl);

        _handleOps(data, from, address(factory), 0, address(0), privKeys);

        // verify that new implementation didn't bricked the wallet
        // verifyWalletUpgrade(oldImpl);
    }

    function _upgradeTo(address proxy, address _newImpl, uint256 signerPk) internal {
        address payable from = payable(kintoAdminWallet);
        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = signerPk;
        privKeys[1] = hardwareWalletType;

        // if UUPS contract has UPGRADE_INTERFACE_VERSION set to 5.0.0, we use upgradeToAndCall
        bytes memory data = abi.encodeWithSelector(UUPSUpgradeable.upgradeTo.selector, address(_newImpl));
        try UUPSUpgradeable5(proxy).UPGRADE_INTERFACE_VERSION() returns (string memory _version) {
            if (keccak256(abi.encode(_version)) == keccak256(abi.encode("5.0.0"))) {
                data = abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, address(_newImpl), bytes(""));
            }
        } catch {}

        _handleOps(data, from, proxy, 0, address(0), privKeys);
    }

    // TODO: should be extended to work with other initialize() that receive params
    function _initialize(address proxy, uint256 signerPk) internal {
        // fund proxy in the paymaster if necessary
        if (_isGethAllowed(proxy)) {
            IInitialize(proxy).initialize();
        } else {
            if (ISponsorPaymaster(payable(_getChainDeployment("SponsorPaymaster"))).balances(proxy) == 0) {
                _fundPaymaster(proxy, signerPk);
            }
            bytes memory selectorAndParams = abi.encodeWithSelector(IInitialize.initialize.selector);
            _handleOps(selectorAndParams, proxy, signerPk);
        }
    }

    /// @notice transfers ownership of a contract to a new owner
    /// @dev from is the KintoWallet-admin
    /// @dev _newOwner cannot be an EOA if contract is not allowed to receive EOA calls
    function _transferOwnership(address proxy, uint256 signerPk, address _newOwner) internal {
        require(_newOwner != address(0), "New owner cannot be 0");

        if (_isGethAllowed(proxy)) {
            Ownable(proxy).transferOwnership(_newOwner);
        } else {
            // we don't want to allow transferring ownership to an EOA (e.g LEDGER_ADMIN) when contract is not allowed to receive EOA calls
            if (_newOwner.code.length == 0) revert("Cannot transfer ownership to EOA");
            _handleOps(abi.encodeWithSelector(Ownable.transferOwnership.selector, _newOwner), proxy, signerPk);
        }
    }

    /// _whitelistApp

    /// @notice whitelists an app in the KintoWallet
    function _whitelistApp(address app, bool whitelist) internal {
        address wallet = kintoAdminWallet;
        address[] memory apps = new address[](1);
        apps[0] = app;

        bool[] memory flags = new bool[](1);
        flags[0] = whitelist;

        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = hardwareWalletType;

        _handleOps(
            abi.encodeWithSelector(IKintoWallet.whitelistApp.selector, apps, flags),
            wallet,
            wallet,
            0,
            address(0),
            privKeys
        );
    }

    function _whitelistApp(address app, address wallet, uint256 signerPk, bool whitelist) internal {
        address[] memory apps = new address[](1);
        apps[0] = app;

        bool[] memory flags = new bool[](1);
        flags[0] = whitelist;

        _handleOps(abi.encodeWithSelector(IKintoWallet.whitelistApp.selector, apps, flags), wallet, wallet, signerPk);
    }

    function _whitelistApp(address app) internal {
        _whitelistApp(app, true);
    }

    /// _handleOps

    function _handleOps(bytes memory selectorAndParams, address to) internal {
        uint256[] memory privateKeys = new uint256[](2);
        privateKeys[0] = deployerPrivateKey;
        privateKeys[1] = hardwareWalletType;
        _handleOps(selectorAndParams, payable(kintoAdminWallet), to, 0, address(0), privateKeys);
    }

    function _handleOps(bytes memory selectorAndParams, address to, uint256 signerPk) internal {
        _handleOps(selectorAndParams, payable(kintoAdminWallet), to, address(0), signerPk);
    }

    function _handleOps(bytes memory selectorAndParams, address from, address to, uint256 signerPk) internal {
        _handleOps(selectorAndParams, from, to, address(0), signerPk);
    }

    function _handleOps(
        bytes memory selectorAndParams,
        address from,
        address to,
        address sponsorPaymaster,
        uint256 signerPk
    ) internal {
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = signerPk;
        _handleOps(selectorAndParams, from, to, 0, sponsorPaymaster, privateKeys);
    }

    // @notice handles ops with custom params
    // @dev receives a hardware wallet type (e.g "trezor", "ledger", "none")
    // if _hwType is "trezor" or "ledger", it will sign the user op with the hardware wallet
    function _handleOps(
        bytes memory selectorAndParams,
        address from,
        address to,
        uint256 value,
        address sponsorPaymaster,
        uint256[] memory privateKeys
    ) internal {
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            block.chainid,
            from,
            to,
            value,
            IKintoWallet(from).getNonce(),
            privateKeys,
            selectorAndParams,
            sponsorPaymaster
        );
        vm.broadcast(deployerPrivateKey);
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(privateKeys[0])));
    }

    /// _handleOpsBatch

    function _handleOpsBatch(bytes[] memory selectorAndParams, address[] memory tos, uint256 signerPk) internal {
        _handleOpsBatch(selectorAndParams, tos, address(0), signerPk);
    }

    function _handleOpsBatch(bytes[] memory selectorAndParams, address to, uint256 signerPk) internal {
        address[] memory tos;
        for (uint256 i = 0; i < selectorAndParams.length; i++) {
            tos[i] = to;
        }
        _handleOpsBatch(selectorAndParams, tos, address(0), signerPk);
    }

    function _handleOpsBatch(bytes[] memory selectorAndParams, address to) internal {
        address[] memory tos = new address[](selectorAndParams.length);
        uint256[] memory privateKeys = new uint256[](2);
        privateKeys[0] = deployerPrivateKey;
        privateKeys[1] = hardwareWalletType;
        for (uint256 i = 0; i < selectorAndParams.length; i++) {
            tos[i] = to;
        }
        _handleOpsBatch(selectorAndParams, tos, address(0), privateKeys);
    }

    // @notice handles ops with multiple ops and destinations
    // @dev uses a sponsorPaymaster
    // @dev does not use a hardware wallet
    function _handleOpsBatch(
        bytes[] memory selectorAndParams,
        address[] memory tos,
        address sponsorPaymaster,
        uint256 signerPk
    ) internal {
        require(selectorAndParams.length == tos.length, "selectorAndParams and tos mismatch");
        address payable from = payable(kintoAdminWallet);
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = signerPk;

        UserOperation[] memory userOps = new UserOperation[](selectorAndParams.length);
        uint256 nonce = IKintoWallet(from).getNonce();
        for (uint256 i = 0; i < selectorAndParams.length; i++) {
            userOps[i] = _createUserOperation(
                block.chainid, from, tos[i], 0, nonce, privateKeys, selectorAndParams[i], sponsorPaymaster
            );
            nonce++;
        }
        vm.broadcast(deployerPrivateKey);
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(signerPk)));
    }

    function _handleOpsBatch(
        bytes[] memory selectorAndParams,
        address[] memory tos,
        address sponsorPaymaster,
        uint256[] memory privateKeys
    ) internal {
        require(selectorAndParams.length == tos.length, "selectorAndParams and tos mismatch");
        address payable from = payable(kintoAdminWallet);

        UserOperation[] memory userOps = new UserOperation[](selectorAndParams.length);
        uint256 nonce = IKintoWallet(from).getNonce();
        for (uint256 i = 0; i < selectorAndParams.length; i++) {
            userOps[i] = _createUserOperation(
                block.chainid, from, tos[i], 0, nonce, privateKeys, selectorAndParams[i], sponsorPaymaster
            );
            nonce++;
        }
        vm.broadcast(deployerPrivateKey);
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(privateKeys[0])));
    }

    function _fundPaymaster(address proxy, uint256 signerPk) internal {
        ISponsorPaymaster _paymaster = ISponsorPaymaster(_getChainDeployment("SponsorPaymaster"));
        vm.broadcast(signerPk);
        _paymaster.addDepositFor{value: 0.00000001 ether}(proxy);
        assertEq(_paymaster.balances(proxy), 0.00000001 ether);
    }

    function _isGethAllowed(address target) internal returns (bool) {
        // contracts allowed to receive EOAs calls
        address[6] memory GETH_ALLOWED_CONTRACTS = [
            _getChainDeployment("EntryPoint"),
            _getChainDeployment("KintoWalletFactory"),
            _getChainDeployment("SponsorPaymaster"),
            _getChainDeployment("KintoID"),
            _getChainDeployment("KintoAppRegistry"),
            _getChainDeployment("BundleBulker")
        ];

        // check if contract is a Geth allowed contract
        for (uint256 i = 0; i < GETH_ALLOWED_CONTRACTS.length; i++) {
            if (target == GETH_ALLOWED_CONTRACTS[i]) {
                return true;
            }
        }

        return false;
    }

    /// @dev By calling upgrade again with the old implementation, we ensure
    /// that the new implementation is at least capable of upgrading itself to
    /// an old version, which is sufficient to fix any issues.
    function verifyWalletUpgrade(address oldImpl) internal {
        vm.startPrank(kintoAdminWallet);
        factory.upgradeAllWalletImplementations(IKintoWallet(oldImpl));
        vm.stopPrank();
    }

    function etchWallet(address wallet) internal {
        console2.log("etching wallet:", vm.toString(wallet));
        KintoWallet impl = new KintoWallet(
            IEntryPoint(_getChainDeployment("EntryPoint")),
            IKintoID(_getChainDeployment("KintoID")),
            IKintoAppRegistry(_getChainDeployment("KintoAppRegistry")),
            IKintoWalletFactory(_getChainDeployment("KintoWalletFactory"))
        );
        vm.etch(wallet, address(impl).code);
    }

    function replaceOwner(IKintoWallet wallet, address newOwner) internal {
        address[] memory owners = new address[](3);
        owners[0] = wallet.owners(0);
        owners[1] = newOwner;
        owners[2] = wallet.owners(2);

        uint8 policy = wallet.signerPolicy();
        vm.prank(address(wallet));
        wallet.resetSigners(owners, policy);

        require(wallet.owners(1) == newOwner, "Failed to replace signer");
    }

    function deployBridgedToken(string memory symbol, string memory name, uint256 decimals, string memory startsWith)
        internal
    {
        // deploy token
        bytes memory bytecode = abi.encodePacked(type(BridgedToken).creationCode, abi.encode(decimals));
        address implementation = _deployImplementation(name, "V1", bytecode, keccak256(abi.encodePacked(name, symbol)));

        bytes32 initCodeHash = keccak256(abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(implementation, "")));
        (bytes32 salt, address expectedAddress) = mineSalt(initCodeHash, startsWith);

        address proxy = _deployProxy(name, implementation, salt);

        console2.log("Proxy deployed @%s", proxy);
        console2.log("Expected address: %s", expectedAddress);
        assertEq(proxy, expectedAddress);

        _whitelistApp(proxy);

        _handleOps(
            abi.encodeWithSelector(
                BridgedToken.initialize.selector, name, symbol, kintoAdminWallet, kintoAdminWallet, kintoAdminWallet
            ),
            proxy
        );

        BridgedToken bridgedToken = BridgedToken(proxy);

        assertEq(bridgedToken.name(), name);
        assertEq(bridgedToken.symbol(), symbol);
        assertEq(bridgedToken.decimals(), decimals);
        assertTrue(bridgedToken.hasRole(bridgedToken.DEFAULT_ADMIN_ROLE(), kintoAdminWallet), "Admin role not set");
        assertTrue(bridgedToken.hasRole(bridgedToken.MINTER_ROLE(), kintoAdminWallet), "Minter role not set");
        assertTrue(bridgedToken.hasRole(bridgedToken.UPGRADER_ROLE(), kintoAdminWallet), "Upgrader role not set");

        console2.log("All checks passed!");

        console2.log("%s implementation deployed @%s", symbol, implementation);
        console2.log("%s deployed @%s", symbol, address(bridgedToken));

        saveContractAddress(string.concat(symbol, "-impl"), implementation);
        saveContractAddress(symbol, address(bridgedToken));
    }
}

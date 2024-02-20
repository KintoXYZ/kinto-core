// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../../src/wallet/KintoWalletFactory.sol";
import "../../../src/paymasters/SponsorPaymaster.sol";
import "../../../src/apps/KintoAppRegistry.sol";

import "../../../src/interfaces/ISponsorPaymaster.sol";
import "../../../src/interfaces/IKintoWallet.sol";

import "../../../test/helpers/Create2Helper.sol";
import "../../../test/helpers/ArtifactsReader.sol";
import "../../../test/helpers/UserOp.sol";
import "../../../test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IInitialize {
    function initialize() external;
}

contract MigrationHelper is Create2Helper, ArtifactsReader, UserOp {
    using ECDSAUpgradeable for bytes32;

    bool testMode;
    uint256 deployerPrivateKey;
    KintoWalletFactory factory;

    function run() public virtual {
        try vm.envBool("TEST_MODE") returns (bool _testMode) {
            testMode = _testMode;
        } catch {}
        console.log("Running on chain: ", vm.toString(block.chainid));
        console.log("Executing from address", msg.sender);
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        console.log("Deployer is: ", vm.addr(deployerPrivateKey));

        factory = KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));
    }

    /// @dev deploys proxy contract via factory from deployer address
    function _deployProxy(string memory contractName, address implementation) internal returns (address _proxy) {
        bool isEntryPoint = keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked("EntryPoint"));
        bool isWallet = keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked("KintoWallet"));

        if (isWallet || isEntryPoint) revert("EntryPoint and KintoWallet do not use UUPPS Proxy");

        // deploy Proxy contract
        vm.broadcast(deployerPrivateKey);
        bytes memory bytecode = abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(address(implementation), ""));
        _proxy = address(UUPSProxy(payable(factory.deployContract(address(0), 0, bytecode, bytes32(0)))));

        console.log(string.concat(contractName, ": ", vm.toString(address(_proxy))));
    }

    /// @dev deploys implementation contracts via entrypoint from deployer address
    /// @dev if contract is ownable, it will transfer ownership to msg.sender
    function _deployImplementation(string memory contractName, string memory version, bytes memory bytecode)
        internal
        returns (address _impl)
    {
        // deploy new implementation via factory
        vm.broadcast(deployerPrivateKey);
        _impl = factory.deployContract(msg.sender, 0, bytecode, bytes32(0));

        console.log(string.concat(contractName, version, "-impl: ", vm.toString(address(_impl))));
    }

    /// @notice deploys implementation contracts via factory from deployer address and upgrades them
    /// @dev if contract is KintoWallet we call upgradeAllWalletImplementations
    /// @dev if contract is allowed to receive EOA calls, we call upgradeTo directly. Otherwise, we use EntryPoint to upgrade
    function _deployImplementationAndUpgrade(string memory contractName, string memory version, bytes memory bytecode)
        internal
        returns (address _impl)
    {
        bool isWallet = keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked("KintoWallet"));
        address proxy = _getChainDeployment(contractName);

        if (!isWallet) require(proxy != address(0), "Need to execute main deploy script first");

        // (1). deploy new implementation via wallet factory
        _impl = _deployImplementation(contractName, version, bytecode);

        // (2). call upgradeTo to set new implementation
        if (!testMode) {
            if (isWallet) {
                vm.broadcast(); // may require LEDGER_ADMIN
                factory.upgradeAllWalletImplementations(IKintoWallet(_impl));
            } else {
                if (_isGethAllowed(proxy)) {
                    vm.broadcast(); // may require LEDGER_ADMIN
                    UUPSUpgradeable(proxy).upgradeTo(_impl);
                } else {
                    try Ownable(proxy).owner() returns (address owner) {
                        if (owner != _getChainDeployment("KintoWallet-admin")) {
                            console.log(
                                "%s contract is not owned by the KintoWallet-admin, its owner is %s",
                                contractName,
                                vm.toString(owner)
                            );
                            revert("Contract is not owned by KintoWallet-admin");
                        }
                        _upgradeTo(proxy, _impl, deployerPrivateKey);
                    } catch {
                        _upgradeTo(proxy, _impl, deployerPrivateKey);
                    }
                }
            }
        } else {
            if (isWallet) {
                vm.prank(factory.owner());
                factory.upgradeAllWalletImplementations(IKintoWallet(_impl));
            } else {
                // todo: ideally, on testMode, we should use the KintoWallet-admin and adjust tests so they use the handleOps
                try Ownable(proxy).owner() returns (address owner) {
                    vm.prank(owner);
                    UUPSUpgradeable(proxy).upgradeTo(_impl);
                } catch {}
            }
        }
    }

    // utils for doing actions through EntryPoint

    function _upgradeTo(address _proxy, address _newImpl, uint256 _signerPk) internal {
        // prep upgradeTo user op
        address payable _from = payable(_getChainDeployment("KintoWallet-admin"));
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = _signerPk;

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            block.chainid,
            _from,
            _proxy,
            0,
            IKintoWallet(_from).getNonce(),
            privateKeys,
            abi.encodeWithSelector(UUPSUpgradeable.upgradeTo.selector, address(_newImpl)),
            _getChainDeployment("SponsorPaymaster")
        );

        vm.broadcast(_signerPk);
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(_signerPk)));
    }

    // TODO: should be extended to work with other initalize() that receive params
    function _initialize(address _proxy, uint256 _signerPk) internal {
        // fund _proxy in the paymaster if necessary
        if (_isGethAllowed(_proxy)) {
            IInitialize(_proxy).initialize();
        } else {
            if (ISponsorPaymaster(payable(_getChainDeployment("SponsorPaymaster"))).balances(_proxy) == 0) {
                _fundPaymaster(_proxy, _signerPk);
            }
            bytes memory selectorAndParams = abi.encodeWithSelector(IInitialize.initialize.selector);
            _handleOps(selectorAndParams, _proxy, _signerPk);
        }
    }

    /// @notice transfers ownership of a contract to a new owner
    /// @dev from is the KintoWallet-admin
    /// @dev _newOwner cannot be an EOA if contract is not allowed to receive EOA calls
    function _transferOwnership(address _proxy, uint256 _signerPk, address _newOwner) internal {
        require(_newOwner != address(0), "New owner cannot be 0");

        if (_isGethAllowed(_proxy)) {
            Ownable(_proxy).transferOwnership(_newOwner);
        } else {
            // we don't want to allow transferring ownership to an EOA (e.g LEDGER_ADMIN) when contract is not allowed to receive EOA calls
            if (_newOwner.code.length == 0) revert("Cannot transfer ownership to LEDGER_ADMIN");
            _handleOps(abi.encodeWithSelector(Ownable.transferOwnership.selector, _newOwner), _proxy, _signerPk);
        }
    }

    /// @notice whitelists an app in the KintoWallet
    function _whitelistApp(address _app, uint256 _signerPk, bool _whitelist) internal {
        address payable _to = payable(_getChainDeployment("KintoWallet-admin"));
        address[] memory apps = new address[](1);
        apps[0] = _app;

        bool[] memory flags = new bool[](1);
        flags[0] = _whitelist;

        _handleOps(abi.encodeWithSelector(IKintoWallet.whitelistApp.selector, apps, flags), _to, _signerPk);
    }

    function _whitelistApp(address _app, uint256 _signerPk) internal {
        _whitelistApp(_app, _signerPk, true);
    }

    function _handleOps(bytes memory _selectorAndParams, address _to, uint256 _signerPk) internal {
        address payable _from = payable(_getChainDeployment("KintoWallet-admin"));
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = _signerPk;

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            block.chainid,
            _from,
            _to,
            0,
            IKintoWallet(_from).getNonce(),
            privateKeys,
            _selectorAndParams,
            _getChainDeployment("SponsorPaymaster")
        );

        vm.broadcast(deployerPrivateKey);
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(_signerPk)));
    }

    function _fundPaymaster(address _proxy, uint256 _signerPk) internal {
        ISponsorPaymaster _paymaster = ISponsorPaymaster(_getChainDeployment("SponsorPaymaster"));
        vm.broadcast(_signerPk);
        _paymaster.addDepositFor{value: 0.00000001 ether}(_proxy);
        assertEq(_paymaster.balances(_proxy), 0.00000001 ether);
    }

    function _isGethAllowed(address _contract) internal returns (bool _isAllowed) {
        // contracts allowed to receive EOAs calls
        address[5] memory GETH_ALLOWED_CONTRACTS = [
            _getChainDeployment("EntryPoint"),
            _getChainDeployment("KintoWalletFactory"),
            _getChainDeployment("SponsorPaymaster"),
            _getChainDeployment("KintoID"),
            _getChainDeployment("KintoAppRegistry")
        ];

        // check if contract is a geth allowed contract
        for (uint256 i = 0; i < GETH_ALLOWED_CONTRACTS.length; i++) {
            if (_contract == GETH_ALLOWED_CONTRACTS[i]) {
                _isAllowed = true;
                break;
            }
        }
    }

    // @dev this is a workaround to get the address of the KintoWallet-admin in test mode
    function _getChainDeployment(string memory _contractName) internal override returns (address _contract) {
        if (testMode && keccak256(abi.encode(_contractName)) == keccak256(abi.encode("KintoWallet-admin"))) {
            return vm.envAddress("KINTO_ADMIN_WALLET");
        }
        return super._getChainDeployment(_contractName);
    }
}

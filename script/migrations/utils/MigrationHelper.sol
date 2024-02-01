// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../../src/wallet/KintoWalletFactory.sol";
import "../../../src/paymasters/SponsorPaymaster.sol";

import "../../../src/interfaces/ISponsorPaymaster.sol";
import "../../../src/interfaces/IKintoWallet.sol";

import "../../../test/helpers/Create2Helper.sol";
import "../../../test/helpers/ArtifactsReader.sol";
import "../../../test/helpers/UserOp.sol";
import "../../../test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IInitialize {
    function initialize(address anOwner, address _recoverer) external;
}

contract MigrationHelper is Create2Helper, ArtifactsReader, UserOp {
    using ECDSAUpgradeable for bytes32;

    uint256 deployerPrivateKey;
    KintoWalletFactory _walletFactory;

    function run() public virtual {
        console.log("Running on chain: ", vm.toString(block.chainid));
        console.log("Executing from address", msg.sender);

        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        _walletFactory = KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));
    }

    /// @dev deploys proxy contract from deployer
    function deployProxy(string memory contractName, address implementation) public returns (address _proxy) {
        bool isEntryPoint = keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked("EntryPoint"));
        bool isWallet = keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked("KintoWallet"));
        _proxy = _getChainDeployment(contractName);

        if (isWallet || isEntryPoint) revert("EntryPoint and KintoWallet do not use UUPPS Proxy");
        if (_proxy != address(0)) revert("Proxy contract already deployed");

        // deploy Proxy contract using ledger
        vm.broadcast();
        _proxy = address(new UUPSProxy{salt: 0}(address(implementation), ""));

        console.log(string.concat(contractName, ": ", vm.toString(address(_proxy))));
    }

    /// @dev deploys implementation contracts from deployer and upgrades them using LEDGER_ADMIN
    function deployAndUpgrade(string memory contractName, string memory version, bytes memory bytecode)
        public
        returns (address _impl)
    {
        bool isWallet = keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked("KintoWallet"));
        address proxy = _getChainDeployment(contractName);

        if (!isWallet) require(proxy != address(0), "Need to execute main deploy script first");

        // (1). deploy new implementation via wallet factory
        vm.broadcast(deployerPrivateKey);
        _impl = _walletFactory.deployContract(vm.envAddress("LEDGER_ADMIN"), 0, bytecode, bytes32(0));

        console.log(string.concat(contractName, version, "-impl: ", vm.toString(address(_impl))));

        // (2). call upgradeTo to set new implementation
        if (isWallet) {
            vm.broadcast(); // requires LEDGER_ADMIN
            _walletFactory.upgradeAllWalletImplementations(IKintoWallet(_impl));
        } else {
            vm.broadcast(); // requires LEDGER_ADMIN
            UUPSUpgradeable(proxy).upgradeTo(_impl);
        }
    }

    // utils for doing actions through EntryPoint

    function _upgradeTo(address _proxy, address _newImpl, uint256 _signerPk) internal {
        address payable _from = payable(_getChainDeployment("KintoWallet-admin"));

        // prep upgradeTo user op
        uint256 nonce = IKintoWallet(_from).getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = _signerPk;
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            block.chainid,
            _from,
            _proxy,
            0,
            nonce,
            privateKeys,
            abi.encodeWithSelector(UUPSUpgradeable.upgradeTo.selector, address(_newImpl)),
            _getChainDeployment("SponsorPaymaster")
        );

        vm.broadcast(deployerPrivateKey);
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(_signerPk)));
    }

    function _initialize(address _proxy, uint256 _signerPk) internal {
        address payable _from = payable(_getChainDeployment("KintoWallet-admin"));

        // fund _proxy in the paymaster
        require(
            ISponsorPaymaster(payable(_getChainDeployment("SponsorPaymaster"))).balances(_proxy) > 0,
            "Need to fund proxy in paymaster"
        );

        // todo: move to a fund function
        // ISponsorPaymaster _paymaster = ISponsorPaymaster(_getChainDeployment("SponsorPaymaster"));
        // vm.broadcast(deployerPrivateKey);
        // _paymaster.addDepositFor{value: 0.00000001 ether}(_proxy);
        // assertEq(_paymaster.balances(_proxy), 0.00000001 ether);

        // prep upgradeTo user op
        uint256 nonce = IKintoWallet(_from).getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = _signerPk;

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            block.chainid,
            _from,
            _proxy,
            0,
            nonce,
            privateKeys,
            abi.encodeWithSelector(IInitialize.initialize.selector),
            _getChainDeployment("SponsorPaymaster")
        );

        vm.broadcast(deployerPrivateKey);
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(_signerPk)));
    }

    function _transferOwnership(address _proxy, uint256 _signerPk, address _newOwner) internal {
        address payable _from = payable(_getChainDeployment("KintoWallet-admin"));

        // prep upgradeTo user op
        uint256 nonce = IKintoWallet(_from).getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = _signerPk;

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            block.chainid,
            _from,
            _proxy,
            0,
            nonce,
            privateKeys,
            abi.encodeWithSelector(Ownable.transferOwnership.selector, _newOwner),
            _getChainDeployment("SponsorPaymaster")
        );

        vm.broadcast(deployerPrivateKey);
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(_signerPk)));
    }
}

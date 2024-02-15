// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "@oz/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../../src/interfaces/IKintoWalletFactory.sol";
import "../../src/interfaces/IKintoWallet.sol";
import "../../src/interfaces/ISponsorPaymaster.sol";

import "../../src/Faucet.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UUPSProxy.sol";
import "../../test/helpers/UserOp.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract FaucetV3 is Faucet {
    constructor(address _kintoWalletFactory) Faucet(_kintoWalletFactory) {}
}

contract KintoMigration15DeployScript is Create2Helper, ArtifactsReader, UserOp {
    using MessageHashUtils for bytes32;

    FaucetV3 _implementation;
    UUPSProxy _proxy;

    function setUp() public {}

    function run() public {
        console.log("Chain ID", vm.toString(block.chainid));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        console.log("Deployer address: ", vm.addr(deployerPrivateKey));

        vm.startBroadcast(deployerPrivateKey);

        address faucetProxy = payable(_getChainDeployment("Faucet"));
        require(faucetProxy != address(0), "Faucet proxy is already deployed");

        // make sure wallet faucet v3 is not deployed
        require(_getChainDeployment("FaucetV3-impl") == address(0), "Faucet v3 is already deployed");

        // use wallet factory to deploy new Faucet implementation
        address factory = _getChainDeployment("KintoWalletFactory");
        IKintoWalletFactory walletFactory = IKintoWalletFactory(payable(factory));

        // deploy Faucet implementation
        bytes memory bytecode = abi.encodePacked(type(FaucetV3).creationCode, abi.encode(factory));
        _implementation = FaucetV3(payable(walletFactory.deployContract(msg.sender, 0, bytecode, bytes32(0))));

        _upgradeTo(address(_implementation), deployerPrivateKey);

        vm.stopBroadcast();

        console.log(string.concat("Faucet-impl: ", vm.toString(address(_implementation))));
    }

    function _upgradeTo(address _newFaucetImpl, uint256 _signerPk) internal {
        address payable adminWallet = payable(_getChainDeployment("KintoWallet-admin"));
        address payable faucetProxy = payable(_getChainDeployment("Faucet"));

        // prep upgradeTo user op
        uint256 nonce = IKintoWallet(adminWallet).getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = _signerPk;
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = _createUserOperation(
            block.chainid,
            adminWallet,
            faucetProxy,
            0,
            nonce,
            privateKeys,
            abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, address(_newFaucetImpl), bytes("")),
            _getChainDeployment("SponsorPaymaster")
        );

        // execute transaction via entry point
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(_signerPk)));
    }
}

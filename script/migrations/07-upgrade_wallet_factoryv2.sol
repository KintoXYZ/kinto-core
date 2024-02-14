// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../src/wallet/KintoWalletFactory.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoWalletFactoryV2 is KintoWalletFactory {
    constructor(IKintoWallet _impl) KintoWalletFactory(_impl) {}

    function newFunction() public pure returns (uint256) {
        return 1;
    }
}

contract KintoMigration7DeployScript is Create2Helper, ArtifactsReader {
    using MessageHashUtils for bytes32;

    KintoWalletFactory _factoryImpl;
    UUPSProxy _proxy;

    function setUp() public {}

    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // Execute this script with the ledger admin but we also execute stuff with the hot wallet
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        console.log("Executing with address", msg.sender);
        address factoryAddr = _getChainDeployment("KintoWalletFactory");
        if (factoryAddr == address(0)) {
            console.log("Need to execute main deploy script first", factoryAddr);
            return;
        }
        IOldWalletFactory _walletFactory = IOldWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));

        address newImpl = _getChainDeployment("KintoWalletV2-impl");
        if (newImpl == address(0)) {
            console.log("Need to deploy the new wallet first", newImpl);
            return;
        }
        bytes memory bytecode = abi.encodePacked(
            type(KintoWalletFactoryV2).creationCode,
            abi.encode(_getChainDeployment("KintoWalletV2-impl")) // Encoded constructor arguments
        );

        // Deploy new paymaster implementation
        _factoryImpl = KintoWalletFactoryV2(payable(_walletFactory.deployContract(0, bytecode, bytes32(0))));
        vm.stopBroadcast();
        // Switch to admin
        vm.startBroadcast();
        // Upgrade
        KintoWalletFactory(address(_walletFactory)).upgradeToAndCall(address(_factoryImpl), bytes(""));
        vm.stopBroadcast();
        // Writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"KintoWalletFactoryV2-impl": "', vm.toString(address(_factoryImpl)), '"'));
    }
}

interface IOldWalletFactory {
    function deployContract(uint256 amount, bytes calldata bytecode, bytes32 salt) external payable returns (address);
}

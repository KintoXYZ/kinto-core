// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/wallet/KintoWallet.sol";
import "../../src/paymasters/SponsorPaymaster.sol";
import "../../src/KintoID.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoMigration14DeployScript is Create2Helper, ArtifactsReader {
    using ECDSAUpgradeable for bytes32;

    KintoWalletFactoryV3 _factoryImpl;

    function setUp() public {}

    // NOTE: this migration must be run from the ledger admin
    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // Execute this script with the ledger admin but first we use the hot wallet
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        console.log("Executing with address", msg.sender);
        address factoryAddr = _getChainDeployment("KintoWalletFactory");
        if (factoryAddr == address(0)) {
            console.log("Need to execute main deploy script first", factoryAddr);
            return;
        }
        address v3factory = _getChainDeployment("KintoWalletFactoryV3-impl");
        if (v3factory != address(0)) {
            console.log("V3 already deployed", v3factory);
            return;
        }
        IKintoWalletFactory _walletFactory = IKintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));

        address newImpl = _getChainDeployment("KintoWalletV3-impl");
        if (newImpl == address(0)) {
            console.log("Need to deploy the new wallet first", newImpl);
            return;
        }
        bytes memory bytecode = abi.encodePacked(
            type(KintoWalletFactoryV3).creationCode,
            abi.encode(_getChainDeployment("KintoWalletV3-impl")) // Encoded constructor arguments
        );

        // 1) Deploy new wallet factory
        _factoryImpl = KintoWalletFactoryV3(
            payable(_walletFactory.deployContract(vm.envAddress("LEDGER_ADMIN"), 0, bytecode, bytes32(0)))
        );
        vm.stopBroadcast();
        // Start admin
        vm.startBroadcast();
        // 2) Upgrade wallet factory
        KintoWalletFactory(address(_walletFactory)).upgradeTo(address(_factoryImpl));
        vm.stopBroadcast();
        // writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"KintoWalletFactoryV3-impl": "', vm.toString(address(newImpl)), '"'));
    }
}

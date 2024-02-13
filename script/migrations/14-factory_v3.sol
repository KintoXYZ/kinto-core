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

contract KintoWalletFactoryV3 is KintoWalletFactory {
    constructor(IKintoWallet _implementation) KintoWalletFactory(_implementation) {}
}

contract KintoIDV4 is KintoID {
    constructor(address _walletFactory) KintoID(_walletFactory) {}
}

contract KintoMigration14DeployScript is Create2Helper, ArtifactsReader {
    using ECDSAUpgradeable for bytes32;

    KintoWalletFactoryV3 _factoryImpl;
    KintoID _kintoID;
    KintoIDV4 _kintoIDImpl;

    function setUp() public {}

    // NOTE: this migration must be run from the ledger admin
    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // Execute this script with the ledger admin but first we use the hot wallet
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        console.log("Executing with address", msg.sender, vm.envAddress("LEDGER_ADMIN"));
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

        address kintoIDAddr = _getChainDeployment("KintoID");
        if (kintoIDAddr == address(0)) {
            console.log("Need to execute main deploy script first", kintoIDAddr);
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
            abi.encode(newImpl) // Encoded constructor arguments
        );

        // 1) Deploy new wallet factory
        _factoryImpl = KintoWalletFactoryV3(
            payable(_walletFactory.deployContract(vm.envAddress("LEDGER_ADMIN"), 0, bytecode, bytes32(0)))
        );

        // (2). deploy new kinto ID implementation via wallet factory

        _kintoID = KintoID(payable(kintoIDAddr));
        bytecode = abi.encodePacked(type(KintoIDV4).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        _kintoIDImpl =
            KintoIDV4(payable(_walletFactory.deployContract(vm.envAddress("LEDGER_ADMIN"), 0, bytecode, bytes32(0))));

        vm.stopBroadcast();
        // Start admin
        vm.startBroadcast();
        // 3) Upgrade wallet factory
        KintoWalletFactory(address(_walletFactory)).upgradeTo(address(_factoryImpl));
        // (4). upgrade kinto id to new implementation
        _kintoID.upgradeTo(address(_kintoIDImpl));
        vm.stopBroadcast();
        // writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"KintoWalletFactoryV3-impl": "', vm.toString(address(_factoryImpl)), '"'));
        console.log(string.concat('"KintoIDV4-impl": "', vm.toString(address(_kintoIDImpl)), '"'));
    }
}

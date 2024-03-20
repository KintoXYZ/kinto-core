// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/wallet/KintoWallet.sol";
import "../../src/paymasters/SponsorPaymaster.sol";
import "../../src/KintoID.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UUPSProxy.sol";
import "./utils/MigrationHelper.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoWalletFactoryV5 is KintoWalletFactory {
    constructor(IKintoWallet _implAddressP) KintoWalletFactory(_implAddressP) {}
}

contract KintoMigration16DeployScript is Create2Helper, ArtifactsReader {
    using ECDSAUpgradeable for bytes32;

    KintoWalletFactoryV5 _factoryImpl;

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
        address v5factory = _getChainDeployment("KintoWalletFactoryV5-impl");
        if (v5factory != address(0)) {
            console.log("V5 already deployed", v5factory);
            return;
        }

        IKintoWalletFactory _walletFactory = IKintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));

        address newImpl = _getChainDeployment("KintoWalletV3-impl");
        if (newImpl == address(0)) {
            console.log("Need to deploy the new wallet first", newImpl);
            return;
        }

        bytes memory bytecode = abi.encodePacked(
            type(KintoWalletFactoryV5).creationCode,
            abi.encode(newImpl) // Encoded constructor arguments
        );

        // 1) Deploy new wallet factory
        _factoryImpl = KintoWalletFactoryV5(
            payable(_walletFactory.deployContract(vm.envAddress("LEDGER_ADMIN"), 0, bytecode, bytes32(0)))
        );

        vm.stopBroadcast();
        // Start admin
        vm.startBroadcast();
        // 2) Upgrade wallet factory
        KintoWalletFactory(address(_walletFactory)).upgradeTo(address(_factoryImpl));
        // 3) Send ETH to test signer
        KintoWalletFactory(address(_walletFactory)).sendMoneyToAccount{value: 0.05 ether}(
            0x0C1df30B4576A1A94D9528854516D4d425Cf9323
        );
        require(address(0x0C1df30B4576A1A94D9528854516D4d425Cf9323).balance > 0.05 ether, "amount was not sent");
        vm.stopBroadcast();
        // writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"KintoWalletFactoryV5-impl": "', vm.toString(address(_factoryImpl)), '"'));
    }
}

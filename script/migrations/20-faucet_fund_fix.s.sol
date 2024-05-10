// SPDX-License-Identifier: MIT
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

contract KintoMigration20DeployScript is Create2Helper, ArtifactsReader {
    using ECDSAUpgradeable for bytes32;

    KintoWalletFactoryV6 _factoryImpl;

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
            type(KintoWalletFactoryV6).creationCode,
            abi.encode(newImpl) // Encoded constructor arguments
        );

        // 1) Deploy new wallet factory
        _factoryImpl = KintoWalletFactoryV6(
            payable(_walletFactory.deployContract(vm.envAddress("LEDGER_ADMIN"), 0, bytecode, bytes32(0)))
        );

        // 2) Send ETH to faucet
        address _faucet = _getChainDeployment("Faucet");
        KintoWalletFactory(address(_walletFactory)).sendMoneyToAccount{value: 0.7 ether}(_faucet);
        require(address(_faucet).balance >= 0.7 ether, "amount was not sent");
        vm.stopBroadcast();
        // Start admin
        vm.startBroadcast();
        // 3) Upgrade wallet factory
        KintoWalletFactory(address(_walletFactory)).upgradeTo(address(_factoryImpl));
        // writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"KintoWalletFactoryV6-impl": "', vm.toString(address(_factoryImpl)), '"'));
    }
}

contract KintoWalletFactoryV6 is KintoWalletFactory {
    constructor(IKintoWallet _implAddressP) KintoWalletFactory(_implAddressP) {}
}

contract KintoWalletV3 is KintoWallet {
    constructor(IEntryPoint _entryPoint, IKintoID _kintoID, IKintoAppRegistry _appRegistry)
        KintoWallet(_entryPoint, _kintoID, _appRegistry)
    {}
}

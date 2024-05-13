// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/wallet/KintoWallet.sol";
import "../../src/paymasters/SponsorPaymaster.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoMigration10DeployScript is Create2Helper, ArtifactsReader {
    KintoWalletFactory _walletFactory;
    KintoWalletV3 _kintoWalletImpl;
    UUPSProxy _proxy;

    function setUp() public {}

    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // Execute this script with the hot wallet
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        console.log("Executing with address", msg.sender);
        address walletFactoryAddr = _getChainDeployment("KintoWalletFactory");
        if (walletFactoryAddr == address(0)) {
            console.log("Need to execute main deploy script first", walletFactoryAddr);
            return;
        }
        address kintoAppAddr = _getChainDeployment("KintoAppRegistry");
        if (kintoAppAddr == address(0)) {
            console.log("Need to deploy kinto app registry first", kintoAppAddr);
            return;
        }
        _walletFactory = KintoWalletFactory(payable(walletFactoryAddr));

        bytes memory bytecode = abi.encodePacked(
            type(KintoWalletV3).creationCode,
            abi.encode(
                _getChainDeployment("EntryPoint"),
                IKintoID(_getChainDeployment("KintoID")),
                IKintoAppRegistry(_getChainDeployment("KintoAppRegistry"))
            ) // Encoded constructor arguments
        );

        // Deploy new wallet implementation
        _kintoWalletImpl = KintoWalletV3(payable(_walletFactory.deployContract(msg.sender, 0, bytecode, bytes32(0))));
        vm.stopBroadcast();
        vm.startBroadcast();
        // Upgrade all implementations
        _walletFactory.upgradeAllWalletImplementations(_kintoWalletImpl);
        address credits = _getChainDeployment("EngenCredits");
        // Fund in the paymaster
        SponsorPaymaster _paymaster = SponsorPaymaster(payable(_getChainDeployment("SponsorPaymaster")));
        _paymaster.addDepositFor{value: 1e17}(credits);
        vm.stopBroadcast();
        // Writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"KintoWalletV3-impl": "', vm.toString(address(_kintoWalletImpl)), '"'));
    }
}

contract KintoWalletV3 is KintoWallet {
    constructor(IEntryPoint _entryPoint, IKintoID _kintoID, IKintoAppRegistry _appRegistry)
        KintoWallet(_entryPoint, _kintoID, _appRegistry)
    {}
}

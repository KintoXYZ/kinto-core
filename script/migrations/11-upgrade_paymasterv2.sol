// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/paymasters/SponsorPaymaster.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UUPSProxy.sol";
import "./utils/MigrationHelper.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoMigration11DeployScript is Create2Helper, ArtifactsReader {
    using MessageHashUtils for bytes32;

    SponsorPaymaster _paymaster;
    KintoWalletFactory _walletFactory;
    SponsorPaymasterV2 _paymasterImpl;
    UUPSProxy _proxy;

    function setUp() public {}

    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // Execute this script with the hot wallet and ledger
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address sponsorAddr = _getChainDeployment("SponsorPaymaster");
        if (sponsorAddr == address(0)) {
            console.log("Need to execute main deploy script first", sponsorAddr);
            return;
        }
        _paymaster = SponsorPaymaster(payable(sponsorAddr));

        _walletFactory = KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));
        bytes memory bytecode = abi.encodePacked(
            type(SponsorPaymasterV2).creationCode,
            abi.encode(_getChainDeployment("EntryPoint")) // Encoded constructor arguments
        );

        // Deploy new paymaster implementation
        _paymasterImpl = SponsorPaymasterV2(payable(_walletFactory.deployContract(msg.sender, 0, bytecode, bytes32(0))));
        // Switch to admin to upgrade
        vm.stopBroadcast();
        vm.startBroadcast();
        Upgradeable(address(_paymaster)).upgradeTo(address(_paymasterImpl));
        // Set the app registry
        _paymaster.setAppRegistry(_getChainDeployment("KintoAppRegistry"));
        vm.stopBroadcast();
        // Writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"SponsorPaymasterV2-impl": "', vm.toString(address(_paymasterImpl)), '"'));
    }
}

contract SponsorPaymasterV2 is SponsorPaymaster {
    constructor(IEntryPoint __entryPoint) SponsorPaymaster(__entryPoint) {}
}

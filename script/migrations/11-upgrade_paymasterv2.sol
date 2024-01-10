// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/paymasters/SponsorPaymaster.sol";
import {KintoWallet} from "../../src/wallet/KintoWallet.sol";
import {Create2Helper} from "../../test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "../../test/helpers/UUPSProxy.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/console.sol";

contract KintoMigration9DeployScript is Create2Helper, ArtifactsReader {
    using ECDSAUpgradeable for bytes32;

    SponsorPaymaster _paymaster;
    KintoWalletFactory _walletFactory;
    SponsorPaymasterV2 _paymasterImpl;
    UUPSProxy _proxy;

    function setUp() public {}

    // solhint-disable code-complexity
    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // Execute this script with the hot wallet and ledger
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.rememberKey(deployerPrivateKey);
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
        _paymaster.upgradeTo(address(_paymasterImpl));
        // Set the app registry
        _paymaster.setAppRegistry(_getChainDeployment("KintoAppRegistry"));
        vm.stopBroadcast();
        // Writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"SponsorPaymasterV2-impl": "', vm.toString(address(_paymasterImpl)), '"'));
    }
}

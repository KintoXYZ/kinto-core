// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "../../src/apps/KintoAppRegistry.sol";
import "../../src/paymasters/SponsorPaymaster.sol";
import "../../src/wallet/KintoWalletFactory.sol";
import {Create2Helper} from "../../test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "../../test/helpers/UUPSProxy.sol";
import "@oz/contracts/utils/cryptography/MessageHashUtils.sol";
import "@oz/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/console.sol";

contract KintoMigration9DeployScript is Create2Helper, ArtifactsReader {
    using MessageHashUtils for bytes32;

    KintoAppRegistry _kintoApp;
    KintoAppRegistry _kintoAppImpl;

    function setUp() public {}

    // solhint-disable code-complexity
    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // Execute this script with the hot wallet
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        console.log("Executing with address", msg.sender);
        address ledgerAdmin = vm.envAddress("LEDGER_ADMIN");
        console.log("Executing with ledger admin as", ledgerAdmin);

        address appAddr = _getChainDeployment("KintoAppRegistry");
        if (appAddr != address(0)) {
            console.log("KintoAppRegistry already deployed", appAddr);
            return;
        }
        address walletFactoryAddr = _getChainDeployment("KintoWalletFactory");
        KintoWalletFactory _walletFactory = KintoWalletFactory(walletFactoryAddr);
        address kintoAppRegistryImpl = _getChainDeployment("KintoAppRegistry-impl");

        if (kintoAppRegistryImpl == address(0)) {
            console.log("kintoAppRegistryImpl not deployed", appAddr);
            return;
        }
        console.log("kintoAppRegistryImpl", kintoAppRegistryImpl);
        bytes memory bytecode =
            abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(address(kintoAppRegistryImpl), bytes("")));
        // deploy _proxy contract and point it to _implementation
        _kintoApp = KintoAppRegistry(_walletFactory.deployContract{value: 0}(ledgerAdmin, 0, bytecode, bytes32("10")));
        vm.stopBroadcast();

        // Writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"KintoAppRegistry": "', vm.toString(address(_kintoApp)), '"'));
    }
}

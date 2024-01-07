// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../../src/apps/KintoAppRegistry.sol";
import "../../src/paymasters/SponsorPaymaster.sol";
import "../../src/interfaces/IKintoWalletFactory.sol";
import {Create2Helper} from "../../test/helpers/Create2Helper.sol";
import {ArtifactsReader} from "../../test/helpers/ArtifactsReader.sol";
import {UUPSProxy} from "../../test/helpers/UUPSProxy.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/console.sol";

contract KintoMigration7DeployScript is Create2Helper, ArtifactsReader {
    using ECDSAUpgradeable for bytes32;

    KintoAppRegistry _kintoApp;

    function setUp() public {}

    // solhint-disable code-complexity
    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));
        // Execute this script with the hot wallet, not with ledger
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("LEGER_ADMIN");
        if (admin == address(0)) {
            console.log("Admin key not set", admin);
            return;
        }
        vm.startBroadcast(deployerPrivateKey);
        console.log("Executing with address", msg.sender);
        vm.startBroadcast();
        address appAddr = _getChainDeployment("KintoAppRegistry");
        if (appAddr != address(0)) {
            console.log("KintoAppRegistry already deployed", appAddr);
            return;
        }
        address walletFactoryAddr = _getChainDeployment("KintoWalletFactory");
        IKintoWalletFactory _walletFactory = IKintoWalletFactory(walletFactoryAddr);
        _kintoApp = KintoAppRegistry(
            _walletFactory.deployContract(
                msg.sender, 0, abi.encodePacked(type(KintoAppRegistry).creationCode), bytes32(0)
            )
        );
        // Give ownership to admin
        _kintoApp.transferOwnership(admin);
        address credits = _getChainDeployment("EngenCredits");
        // Create Engen App
        _kintoApp.registerApp("Engen", credits, new address[](0), [uint256(0), uint256(0), uint256(0), uint256(0)]);
        // Fund in the paymaster
        SponsorPaymaster _paymaster = SponsorPaymaster(payable(_getChainDeployment("SponsorPaymaster")));
        _paymaster.addDepositFor{value: 1e17}(credits);
        vm.stopBroadcast();
        // Writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"KintoAppRegistry": "', vm.toString(address(_kintoApp)), '"'));
    }
}

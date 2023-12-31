// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Script.sol';
import '../../src/wallet/KintoWalletFactory.sol';
import '../../src/KintoID.sol';
import { KintoWalletV2 } from '../../src/wallet/KintoWallet.sol';
import { Create2Helper } from '../../test/helpers/Create2Helper.sol';
import { ArtifactsReader } from '../../test/helpers/ArtifactsReader.sol';
import { UUPSProxy } from '../../test/helpers/UUPSProxy.sol';
import {KYCSignature} from '../../test/helpers/KYCSignature.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import 'forge-std/console.sol';

contract KintoMigration3DeployScript is Create2Helper, KYCSignature, ArtifactsReader {
    using ECDSAUpgradeable for bytes32;

    KintoWalletFactory _walletFactory;
    KintoWallet _kintoWalletv1;
    KintoID _kintoIDv1;
    UUPSProxy _proxy;

    function setUp() public {}

    // solhint-disable code-complexity
    function run() public {

        console.log('RUNNING ON CHAIN WITH ID', vm.toString(block.chainid));
        // If not using ledger, replace
        // uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
        // vm.startBroadcast(deployerPrivateKey);
        console.log('Executing with address', msg.sender);
        vm.startBroadcast();
        address walletFactoryAddr = _getChainDeployment('KintoWalletFactory');
        if (walletFactoryAddr == address(0)) {
            console.log('Need to execute main deploy script first', walletFactoryAddr);
            return;
        }
        // Mint an nft to the owner
        _kintoIDv1 = KintoID(_getChainDeployment('KintoID'));
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(
            _kintoIDv1, msg.sender, msg.sender, 1, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 0; // ADMIN
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        // deploy walletv1 through wallet factory and initializes it
        _kintoWalletv1 = KintoWallet(payable(address(_walletFactory.createAccount(msg.sender, msg.sender, 0))));
        vm.stopBroadcast();

        // Writes the addresses to a file
        console.log('Add these new addresses to the artifacts file');
        console.log(string.concat('"KintoWalletV2-impl": "', vm.toString(address(_kintoWalletv1)), '"'));
    }
}

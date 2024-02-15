// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import "./utils/MigrationHelper.sol";

// NOTE: this is a sample migration script with the new refactors
// contract KintoMigration22DeployScript is MigrationHelper {
//     using MessageHashUtils for bytes32;

//     function run() public {
//         super.run();

//         // generate bytecode for KintoWalletV5
//         bytes memory bytecode = abi.encodePacked(
//             type(KintoWalletV5).creationCode,
//             abi.encode(
//                 _getChainDeployment("EntryPoint"),
//                 IKintoID(_getChainDeployment("KintoID")),
//                 IKintoAppRegistry(_getChainDeployment("KintoAppRegistry"))
//             )
//         );

//         // upgrade KintoWallet to V5
//         deployAndUpgrade("KintoWallet", "V5", bytecode);
//     }
// }

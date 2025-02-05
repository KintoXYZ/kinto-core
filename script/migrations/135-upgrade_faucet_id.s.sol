// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {KintoID} from "../../src/KintoID.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

contract UpgradeKintoIDScript is MigrationHelper {
    function run() public override {
        super.run();

        bytes memory bytecode = abi.encodePacked(
            type(KintoID).creationCode,
            abi.encode(_getChainDeployment("KintoWalletFactory"), _getChainDeployment("Faucet"))
        );

        address impl = _deployImplementationAndUpgrade("KintoID", "V11", bytecode);
        saveContractAddress("KintoIDV11-impl", impl);

        KintoID kintoID = KintoID(_getChainDeployment("KintoID"));
        address nioGovernor = _getChainDeployment("NioGovernor");
        bytes32 governanceRole = kintoID.GOVERNANCE_ROLE();

        assertTrue(kintoID.hasRole(governanceRole, kintoAdminWallet));
        assertTrue(kintoID.hasRole(governanceRole, nioGovernor));

        assertTrue(kintoID.isKYC(deployer));
    }
}

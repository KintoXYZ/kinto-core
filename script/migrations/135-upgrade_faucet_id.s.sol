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

        address impl = _deployImplementationAndUpgrade("KintoID", "V9", bytecode);
        saveContractAddress("KintoIDV9-impl", impl);

        KintoID kintoID = KintoID(_getChainDeployment("KintoID"));
        address nioGovernor = _getChainDeployment("NioGovernor");
        bytes32 governanceRole = kintoID.GOVERNANCE_ROLE();

        assertFalse(kintoID.hasRole(governanceRole, kintoAdminWallet));
        assertFalse(kintoID.hasRole(governanceRole, nioGovernor));

        _handleOps(
            abi.encodeWithSelector(IAccessControl.grantRole.selector, governanceRole, kintoAdminWallet),
            address(kintoID)
        );

        _handleOps(
            abi.encodeWithSelector(IAccessControl.grantRole.selector, governanceRole, nioGovernor), address(kintoID)
        );

        assertTrue(kintoID.hasRole(kintoID.GOVERNANCE_ROLE(), kintoAdminWallet));
        assertTrue(kintoID.hasRole(kintoID.GOVERNANCE_ROLE(), nioGovernor));

        assertTrue(kintoID.isKYC(deployer));
    }
}

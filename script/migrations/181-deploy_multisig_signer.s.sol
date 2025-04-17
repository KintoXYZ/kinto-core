// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/MultisigSigner.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";

/**
 * @title DeployMultisigSignerScript
 * @notice Deploys the MultisigSigner contract with KintoAdmin as the owner
 * @dev This script deploys both the implementation and proxy contracts
 */
contract DeployMultisigSignerScript is MigrationHelper {
    function run() public override {
        super.run();

        console2.log("Deploying MultisigSigner contract");

        // Get EntryPoint address
        address entryPointAddress = _getChainDeployment("EntryPoint");
        console2.log("EntryPoint address:", entryPointAddress);

        // Get KintoAdmin wallet address
        address adminWallet = kintoAdminWallet;
        console2.log("KintoAdmin wallet address:", adminWallet);

        // Deploy MultisigSigner implementation
        bytes memory bytecode = abi.encodePacked(type(MultisigSigner).creationCode, abi.encode(entryPointAddress));

        address implementation = _deployImplementation("MultisigSigner", "V1", bytecode);

        // Deploy Proxy contract
        address proxy = _deployProxy("MultisigSigner", implementation);

        _whitelistApp(address(proxy));
        // Otherwise, use the _handleOps helper function
        _handleOps(abi.encodeWithSelector(MultisigSigner.initialize.selector, adminWallet), proxy);
        console2.log("Initialized MultisigSigner with handleOps");

        // Verify that initialization was successful by checking the owner
        address owner = MultisigSigner(proxy).owner();
        console2.log("Owner of MultisigSigner:", owner);
        require(owner == adminWallet, "Owner is not the KintoAdmin wallet");
        console2.log("Ownership verification successful");

        console2.log("MultisigSigner deployment completed");
        console2.log("Implementation:", implementation);
        console2.log("Proxy:", proxy);

        // Save implementation address
        saveContractAddress("MultisigSigner-impl", implementation);

        // Save proxy address
        saveContractAddress("MultisigSigner", proxy);
    }
}

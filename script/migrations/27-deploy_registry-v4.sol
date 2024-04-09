// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/paymasters/SponsorPaymaster.sol";
import "./utils/MigrationHelper.sol";

contract KintoMigration27DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        bytes memory bytecode =
            abi.encodePacked(type(KintoAppRegistry).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        _deployImplementationAndUpgrade("KintoAppRegistry", "V4", bytecode);

        // -- sanity checks --

        // check KintoID is set on Registry
        IKintoAppRegistry registry = IKintoAppRegistry(_getChainDeployment("KintoAppRegistry"));
        require(address(registry.kintoID()) == _getChainDeployment("KintoID"), "KintoID not set on Registry");

        // check we can't call registerApp without being KYC'd
        try registry.registerApp("test", address(0), new address[](0), [uint256(0), uint256(0), uint256(0), uint256(0)])
        {
            revert("registerApp should revert");
        } catch Error(string memory reason) {
            require(
                keccak256(abi.encodePacked(reason)) == keccak256(abi.encodePacked("KYC required")), "unexpected error"
            );
        }
    }
}

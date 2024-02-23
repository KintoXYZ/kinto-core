// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/paymasters/SponsorPaymaster.sol";
import "./utils/MigrationHelper.sol";

contract KintoMigration26DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        bytes memory bytecode =
            abi.encodePacked(type(SponsorPaymaster).creationCode, abi.encode(_getChainDeployment("EntryPoint")));
        _deployImplementationAndUpgrade("SponsorPaymaster", "V9", bytecode);

        // set Kinto contracts on SponsorPaymaster for inflator
        bytes[] memory selectorsAndParams = new bytes[](6);
        selectorsAndParams[0] =
            abi.encodeWithSelector(SponsorPaymaster.setKintoContract.selector, "KID", _getChainDeployment("KintoID"));
        selectorsAndParams[1] = abi.encodeWithSelector(
            SponsorPaymaster.setKintoContract.selector, "KWF", _getChainDeployment("KintoWalletFactory")
        );
        selectorsAndParams[2] = abi.encodeWithSelector(
            SponsorPaymaster.setKintoContract.selector, "KR", _getChainDeployment("KintoAppRegistry")
        );
        selectorsAndParams[3] = abi.encodeWithSelector(
            SponsorPaymaster.setKintoContract.selector, "SP", _getChainDeployment("SponsorPaymaster")
        );
        selectorsAndParams[4] =
            abi.encodeWithSelector(SponsorPaymaster.setKintoContract.selector, "FCT", _getChainDeployment("Faucet"));
        selectorsAndParams[5] = abi.encodeWithSelector(
            SponsorPaymaster.setKintoContract.selector, "EC", _getChainDeployment("EngenCredits")
        );

        address paymasterProxy = _getChainDeployment("SponsorPaymaster");
        _handleOps(selectorsAndParams, paymasterProxy, deployerPrivateKey);

        // sanity check
        SponsorPaymaster paymaster = SponsorPaymaster(paymasterProxy);
        assertEq(paymaster.kintoContracts("KID"), _getChainDeployment("KintoID"));
        assertEq(paymaster.kintoContracts("KWF"), _getChainDeployment("KintoWalletFactory"));
        assertEq(paymaster.kintoContracts("KR"), _getChainDeployment("KintoAppRegistry"));
        assertEq(paymaster.kintoContracts("SP"), _getChainDeployment("SponsorPaymaster"));
        assertEq(paymaster.kintoContracts("FCT"), _getChainDeployment("Faucet"));
        assertEq(paymaster.kintoContracts("EC"), _getChainDeployment("EngenCredits"));
    }
}

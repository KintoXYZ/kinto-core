// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/inflators/KintoInflator.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration31DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        /// @dev since KintoInflator is owned by the ledger, we can't upgrade so we are both the implementation and the proxy
        bytes memory bytecode = abi.encodePacked(type(KintoInflator).creationCode);
        address implementation = _deployImplementation("KintoInflator", "V1", bytecode);
        address proxy = _deployProxy("KintoInflator", implementation);

        // whitelist the new KintoInflator & initialize
        _whitelistApp(proxy);
        _initialize(proxy, deployerPrivateKey);

        // set Kinto contracts to inflator
        bytes[] memory selectorsAndParams = new bytes[](6);
        selectorsAndParams[0] =
            abi.encodeWithSelector(KintoInflator.setKintoContract.selector, "KID", _getChainDeployment("KintoID"));
        selectorsAndParams[1] = abi.encodeWithSelector(
            KintoInflator.setKintoContract.selector, "KWF", _getChainDeployment("KintoWalletFactory")
        );
        selectorsAndParams[2] = abi.encodeWithSelector(
            KintoInflator.setKintoContract.selector, "KR", _getChainDeployment("KintoAppRegistry")
        );
        selectorsAndParams[3] = abi.encodeWithSelector(
            KintoInflator.setKintoContract.selector, "SP", _getChainDeployment("SponsorPaymaster")
        );
        selectorsAndParams[4] =
            abi.encodeWithSelector(KintoInflator.setKintoContract.selector, "FCT", _getChainDeployment("Faucet"));
        selectorsAndParams[5] =
            abi.encodeWithSelector(KintoInflator.setKintoContract.selector, "EC", _getChainDeployment("EngenCredits"));

        _handleOpsBatch(selectorsAndParams, proxy, deployerPrivateKey);

        // sanity check
        KintoInflator inflator = KintoInflator(proxy);
        assertEq(inflator.kintoContracts("KID"), _getChainDeployment("KintoID"));
        assertEq(inflator.kintoContracts("KWF"), _getChainDeployment("KintoWalletFactory"));
        assertEq(inflator.kintoContracts("KR"), _getChainDeployment("KintoAppRegistry"));
        assertEq(inflator.kintoContracts("SP"), _getChainDeployment("SponsorPaymaster"));
        assertEq(inflator.kintoContracts("FCT"), _getChainDeployment("Faucet"));
        assertEq(inflator.kintoContracts("EC"), _getChainDeployment("EngenCredits"));
    }
}

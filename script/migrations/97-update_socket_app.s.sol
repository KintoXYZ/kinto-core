// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWallet.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";
import "@kinto-core-test/helpers/ArrayHelpers.sol";

contract KintoMigration97DeployScript is MigrationHelper {
    using ArrayHelpers for *;

    function run() public override {
        super.run();

        KintoAppRegistry kintoAppRegistry = KintoAppRegistry(payable(_getChainDeployment("KintoAppRegistry")));

        address socketApp = 0x3e9727470C66B1e77034590926CDe0242B5A3dCc; // Socket-DL contract

        _handleOps(
            abi.encodeWithSelector(
                KintoAppRegistry.addAppContracts.selector,
                socketApp,
                [
                    0x6332e56A423480A211E301Cb85be12814e9238Bb,
                    0x2B98775aBE9cDEb041e3c2E56C76ce2560AF57FB,
                    0x12FF8947a2524303C13ca7dA9bE4914381f6557a,
                    0x72846179EF1467B2b71F2bb7525fcD4450E46B2A,
                    0x897DA4D039f64090bfdb33cd2Ed2Da81adD6FB02,
                    0xa7527C270f30cF3dAFa6e82603b4978e1A849359,
                    0x6dbB5ee7c63775013FaF810527DBeDe2810d7Aee
                ].toMemoryArray()
            ),
            address(_getChainDeployment("KintoAppRegistry"))
        );

        assertEq(kintoAppRegistry.getApp(0x6332e56A423480A211E301Cb85be12814e9238Bb), socketApp);
        assertEq(kintoAppRegistry.getApp(0x6dbB5ee7c63775013FaF810527DBeDe2810d7Aee), socketApp);
    }
}

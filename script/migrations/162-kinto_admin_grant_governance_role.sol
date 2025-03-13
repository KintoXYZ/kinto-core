// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {UUPSUpgradeable} from "@openzeppelin-5.0.1/contracts/proxy/utils/UUPSUpgradeable.sol";
import {BridgedToken} from "@kinto-core/tokens/bridged/BridgedToken.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";

import "forge-std/console2.sol";

contract Script is MigrationHelper {
    function run() public override {
        super.run();

        AccessManager accessManager = AccessManager(_getChainDeployment("AccessManager"));
        address kintoAdmin = 0x2e2B1c42E38f5af81771e65D87729E57ABD1337a;

        _handleOps(
            abi.encodeWithSelector(AccessManager.grantRole.selector, NIO_GOVERNOR_ROLE, kintoAdmin, uint32(NO_DELAY)),
            address(accessManager)
        );

        (bool isMember, uint32 currentDelay) = accessManager.hasRole(NIO_GOVERNOR_ROLE, kintoAdmin);
        assertTrue(isMember);
        assertEq(currentDelay, NO_DELAY);
    }
}

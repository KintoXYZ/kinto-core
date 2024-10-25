// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Treasury} from "@kinto-core/treasury/Treasury.sol";
import {NioElection} from "@kinto-core/governance/NioElection.sol";
import {NioGuardians} from "@kinto-core/tokens/NioGuardians.sol";
import {BridgedKinto} from "@kinto-core/tokens/bridged/BridgedKinto.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {AccessManager} from "@openzeppelin-5.0.1/contracts/access/manager/AccessManager.sol";
import {Ownable} from "@openzeppelin-5.0.1/contracts/access/Ownable.sol";
import {NioGovernor} from "@kinto-core/governance/NioGovernor.sol";
import {IKintoID} from "@kinto-core/interfaces/IKintoID.sol";

import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        AccessManager accessManager = AccessManager(_getChainDeployment("AccessManager"));
        address treasury = _getChainDeployment("Treasury");
        address governor = _getChainDeployment("NioGovernor ");

        _whitelistApp(address(accessManager));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = Treasury.sendFunds.selector;
        selectors[1] = Treasury.sendETH.selector;
        selectors[2] = Treasury.batchSendFunds.selector;

        _handleOps(
            abi.encodeWithSelector(AccessManager.setTargetFunctionRole.selector, treasury, selectors, NIO_GOVERNOR_ROLE),
            address(accessManager)
        );

        _handleOps(
            abi.encodeWithSelector(
                AccessManager.grantRole.selector, NIO_GOVERNOR_ROLE, governor, uint32(NIO_EXECUTION_DELAY)
            ),
            address(accessManager)
        );

        _handleOps(
            abi.encodeWithSelector(AccessManager.labelRole.selector, NIO_GOVERNOR_ROLE, "NIO_GOVERNOR_ROLE"),
            address(accessManager)
        );

        _handleOps(abi.encodeWithSelector(Ownable.transferOwnership.selector, accessManager), address(treasury));

        assertEq(Treasury(payable(treasury)).owner(), address(accessManager));

        (bool immediate, uint32 delay) = accessManager.canCall(governor, treasury, Treasury.sendFunds.selector);
        assertFalse(immediate);
        assertEq(delay, NIO_EXECUTION_DELAY);

        (bool isMember, uint32 currentDelay) = accessManager.hasRole(NIO_GOVERNOR_ROLE, governor);
        assertTrue(isMember);
        assertEq(currentDelay, NIO_EXECUTION_DELAY);
    }
}

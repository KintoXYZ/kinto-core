// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "@openzeppelin-5.0.1/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-5.0.1/contracts/interfaces/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IAccessControl} from "@openzeppelin-5.0.1/contracts/access/IAccessControl.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {RewardsDistributor} from "@kinto-core/liquidity-mining/RewardsDistributor.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {console2} from "forge-std/console2.sol";

contract Script is MigrationHelper {
    using LibString for *;
    using Strings for string;
    using stdJson for string;

    function run() public override {
        super.run();

        bytes32 SOCKET_RELAYER_ROLE = 0xf55a83f13e82a29ee3cdfc818b3fe62cda242e183626adac00b6944a191ec402;
        bytes32 RESCUE_ROLE = 0xc4c453d647953c0fd35db5a34ee76e60fb4abc3a8fb891a25936b70b38f29253;

        address SOCKET_OWNER = 0xB0BBff6311B7F245761A7846d3Ce7B1b100C1836;
        address SOCKET = 0x3e9727470C66B1e77034590926CDe0242B5A3dCc;
        address EXECUTION_MANAGER = 0x6c914cc610e9a05eaFFfD79c10c60Ad1704717E5;
        address SOCKET_BATCHER = 0x1F6bc87f3309B5D31Eb0BdaBE3ED7d3110d3B9c3;

        //        _whitelistApp(address(rewardsDistributor));

        _handleOps(
            abi.encodeWithSelector(IAccessControl.grantRole.selector, SOCKET_RELAYER_ROLE, SOCKET_BATCHER), SOCKET
        );

        _handleOps(
            abi.encodeWithSelector(IAccessControl.grantRole.selector, SOCKET_RELAYER_ROLE, SOCKET_BATCHER),
            EXECUTION_MANAGER
        );

        _handleOps(
            abi.encodeWithSelector(IAccessControl.grantRole.selector, RESCUE_ROLE, SOCKET_OWNER), EXECUTION_MANAGER
        );

        assertTrue(IAccessControl(SOCKET).hasRole(SOCKET_RELAYER_ROLE, SOCKET_BATCHER));
        assertTrue(IAccessControl(EXECUTION_MANAGER).hasRole(SOCKET_RELAYER_ROLE, SOCKET_BATCHER));
        assertTrue(IAccessControl(EXECUTION_MANAGER).hasRole(RESCUE_ROLE, SOCKET_OWNER));

        console2.log("All checks passed!");
    }
}

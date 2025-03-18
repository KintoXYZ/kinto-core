// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {StakedKinto} from "@kinto-core/vaults/StakedKinto.sol";

import {SafeBeaconProxy} from "@kinto-core/proxy/SafeBeaconProxy.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";

import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {
    IERC20Upgradeable,
    IERC20MetadataUpgradeable
} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol';

import "@kinto-core-test/helpers/ArrayHelpers.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployScript is Script, MigrationHelper {
    using ArrayHelpers for *;

    address public constant SOCKET_APP = 0x3e9727470C66B1e77034590926CDe0242B5A3dCc;
    address public constant K = 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87;
    address public constant USDC = 0x05DC0010C9902EcF6CBc921c6A4bd971c69E5A2E;
    //May 15th, 2025, 10:00:00 AM PT.
    uint256 public constant END_TIME = 1747238400;

    function run() public override {
        super.run();

        if (_getChainDeployment("StakedKinto") != address(0)) {
            console2.log("StakedKinto is deployed");
            return;
        }

        vm.broadcast(deployerPrivateKey);
        StakedKinto impl = new StakedKinto();

        (bytes32 salt, address expectedAddress) =
            mineSalt(keccak256(abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(address(impl), ""))), "5A1E00");

        vm.broadcast(deployerPrivateKey);
        UUPSProxy proxy = new UUPSProxy{salt: salt}(address(impl), "");
        StakedKinto stakedKinto = StakedKinto(address(proxy));

        _handleOps(
            abi.encodeWithSelector(
                KintoAppRegistry.addAppContracts.selector, SOCKET_APP, [address(stakedKinto)].toMemoryArray()
            ),
            address(_getChainDeployment("KintoAppRegistry"))
        );

        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = deployerPrivateKey;
        _handleOps(
            abi.encodeWithSelector(StakedKinto.initialize.selector, IERC20MetadataUpgradeable(K), IERC20Upgradeable(USDC), 3, END_TIME, 'Staked Kinto', 'stK', 500_000 * 1e18),
            payable(kintoAdminWallet),
            address(proxy),
            0,
            address(0),
            privateKeys
        );

        assertEq(address(stakedKinto), address(expectedAddress));
        assertEq(address(stakedKinto.rewardToken()), USDC);

        saveContractAddress("stakedKinto", address(stakedKinto));
        saveContractAddress("stakedKinto-impl", address(impl));
    }
}

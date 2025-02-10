// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SealedBidTokenSale} from "@kinto-core/apps/SealedBidTokenSale.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";
import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {UUPSUpgradeable} from "@openzeppelin-5.0.1/contracts/proxy/utils/UUPSUpgradeable.sol";
import "forge-std/console2.sol";

contract Script is MigrationHelper {
    address public constant SOCKET_APP = 0x3e9727470C66B1e77034590926CDe0242B5A3dCc;
    address public constant KINTO = 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87;
    address public constant TREASURY = 0x793500709506652Fcc61F0d2D0fDa605638D4293;
    address public constant USDC = 0x05DC0010C9902EcF6CBc921c6A4bd971c69E5A2E;
    //Tuesday, Feb 11, 2025, 10:00:00 AM PT.
    uint256 public constant PRE_START_TIME = 1739213517;
    //Tuesday, Feb 18, 2025, 10:00:00 AM PT.
    uint256 public constant START_TIME = 1739901600;
    uint256 public constant MINIMUM_CAP = 250_000 * 1e6;

    function run() public override {
        super.run();

        vm.broadcast(deployerPrivateKey);
        SealedBidTokenSale impl = new SealedBidTokenSale(KINTO, TREASURY, USDC, PRE_START_TIME, START_TIME, MINIMUM_CAP);
        saveContractAddress("SealedBidTokenSale-impl", address(impl));

        address proxy = _getChainDeployment("SealedBidTokenSale");
        console2.log("proxy: %s", proxy);

        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = deployerPrivateKey;
        _handleOps(
            abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, address(impl), bytes("")),
            payable(kintoAdminWallet),
            address(proxy),
            0,
            address(0),
            privateKeys
        );
    }
}

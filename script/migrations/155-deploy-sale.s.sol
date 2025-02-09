// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {SealedBidTokenSale} from "@kinto-core/apps/SealedBidTokenSale.sol";

import {SafeBeaconProxy} from "@kinto-core/proxy/SafeBeaconProxy.sol";
import {KintoAppRegistry} from "@kinto-core/apps/KintoAppRegistry.sol";

import {UUPSProxy} from "@kinto-core-test/helpers/UUPSProxy.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

import "@kinto-core-test/helpers/ArrayHelpers.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract DeployScript is Script, MigrationHelper {
    using ArrayHelpers for *;

    address public constant SOCKET_APP = 0x3e9727470C66B1e77034590926CDe0242B5A3dCc;
    address public constant KINTO = 0x010700808D59d2bb92257fCafACfe8e5bFF7aB87;
    address public constant TREASURY = 0x793500709506652Fcc61F0d2D0fDa605638D4293;
    address public constant USDC = 0x05DC0010C9902EcF6CBc921c6A4bd971c69E5A2E;
    //Tuesday, Feb 11, 2025, 10:00:00 AM PT.
    uint256 public constant PRE_START_TIME = 1739296800;
    //Tuesday, Feb 18, 2025, 10:00:00 AM PT.
    uint256 public constant START_TIME = 1739901600;
    uint256 public constant MINIMUM_CAP = 250_000 * 1e6;

    function run() public override {
        super.run();

        if (_getChainDeployment("SealedBidTokenSale") != address(0)) {
            console2.log("SealedBidTokenSale is deployed");
            return;
        }

        vm.broadcast(deployerPrivateKey);
        SealedBidTokenSale impl = new SealedBidTokenSale(KINTO, TREASURY, USDC, PRE_START_TIME, START_TIME, MINIMUM_CAP);

        (bytes32 salt, address expectedAddress) =
            mineSalt(keccak256(abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(address(impl), ""))), "5A1E00");

        vm.broadcast(deployerPrivateKey);
        UUPSProxy proxy = new UUPSProxy{salt: salt}(address(impl), "");
        SealedBidTokenSale sale = SealedBidTokenSale(address(proxy));

        _handleOps(
            abi.encodeWithSelector(
                KintoAppRegistry.addAppContracts.selector, SOCKET_APP, [address(sale)].toMemoryArray()
            ),
            address(_getChainDeployment("KintoAppRegistry"))
        );

        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = deployerPrivateKey;
        _handleOps(
            abi.encodeWithSelector(SealedBidTokenSale.initialize.selector),
            payable(kintoAdminWallet),
            address(proxy),
            0,
            address(0),
            privateKeys
        );

        assertEq(address(sale), address(expectedAddress));
        assertEq(address(sale.USDC()), USDC);

        saveContractAddress("SealedBidTokenSale", address(sale));
        saveContractAddress("SealedBidTokenSale-impl", address(impl));
    }
}

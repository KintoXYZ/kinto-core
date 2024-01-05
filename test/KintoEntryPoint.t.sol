// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/wallet/KintoWallet.sol";
import "../src/wallet/KintoWalletFactory.sol";
import "../src/paymasters/SponsorPaymaster.sol";
import "../src/KintoID.sol";
import {UserOp} from "./helpers/UserOp.sol";
import {UUPSProxy} from "./helpers/UUPSProxy.sol";
import {KYCSignature} from "./helpers/KYCSignature.sol";
import {AATestScaffolding} from "./helpers/AATestScaffolding.sol";

import "@aa/interfaces/IAccount.sol";
import "@aa/core/EntryPoint.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract KintoEntryPointTest is AATestScaffolding, UserOp {
    using ECDSAUpgradeable for bytes32;

    uint256 _chainID = 1;

    function setUp() public {
        vm.chainId(_chainID);
        vm.startPrank(address(1));
        _owner.transfer(1e18);
        vm.stopPrank();
        deployAAScaffolding(_owner, 1, _kycProvider, _recoverer);
    }

    function testUp() public {
        assertEq(_entryPoint.walletFactory(), address(_walletFactory));
    }

    /* ============ Deployment Tests ============ */

    function testCannotResetWalletFactoryAddress() public {
        vm.startPrank(_owner);
        vm.expectRevert("AA36 wallet factory already set");
        _entryPoint.setWalletFactory(address(0));
        vm.stopPrank();
    }
}

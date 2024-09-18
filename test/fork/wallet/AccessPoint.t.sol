// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {stdJson} from "forge-std/StdJson.sol";
import "@kinto-core/interfaces/bridger/IBridger.sol";
import "@kinto-core/bridger/BridgerL2.sol";

import "@kinto-core-test/helpers/UUPSProxy.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/helpers/SignatureHelper.sol";
import "@kinto-core-test/SharedSetup.t.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AccessPointTest is SignatureHelper, SharedSetup {
    function setUp() public override {
        // create Kinto fork
        vm.createSelectFork(vm.rpcUrl("kinto"));

        _entryPoint = IKintoEntryPoint(_getChainDeployment("EntryPoint"));
        _kintoAppRegistry = KintoAppRegistry(_getChainDeployment("KintoAppRegistry"));
        _kintoID = KintoID(_getChainDeployment("KintoID"));
        _walletFactory = KintoWalletFactory(_getChainDeployment("KintoWalletFactory"));

        upgradeWallet();
    }

    function upgradeWallet() internal {
        // Deploy a new wallet implementation
        KintoWallet imp = new KintoWallet(_entryPoint, _kintoID, _kintoAppRegistry, _walletFactory);

        // Upgrade all implementations
        vm.prank(_walletFactory.owner());
        _walletFactory.upgradeAllWalletImplementations(imp);
    }

    function testGetAccessPoint() public {
        KintoWallet admin = KintoWallet(payable(_getChainDeployment("KintoWallet-admin")));

        assertEq(admin.getAccessPoint(), 0x474ec69B0fD5Ebc1EfcFe18B2E8Eb510D755b8C7);
    }
}

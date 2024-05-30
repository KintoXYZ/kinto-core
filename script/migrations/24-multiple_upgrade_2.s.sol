// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/viewers/KYCViewer.sol";
import {MigrationHelper} from "@kinto-core-script/utils/MigrationHelper.sol";

contract KintoMigration24DeployScript is MigrationHelper {
    function run() public override {
        super.run();

        // // upgrade KintoID to V5
        // bytes memory bytecode = abi.encodePacked(type(KintoID).creationCode, abi.encode(""));
        // deployAndUpgrade("KintoID", "V5", bytecode);

        // // upgrade KintoWallet to V5
        // bytecode = abi.encodePacked(
        //     type(KintoWallet).creationCode,
        //     abi.encode(
        //         _getChainDeployment("EntryPoint"),
        //         _getChainDeployment("KintoID"),
        //         _getChainDeployment("KintoAppRegistry")
        //     )
        // );
        // address _walletImplementation = deployAndUpgrade("KintoWallet", "V5", bytecode);

        // // upgrade KintoWalletFactory to V8
        // bytecode = abi.encodePacked(type(KintoWalletFactory).creationCode, abi.encode(_walletImplementation));
        // deployAndUpgrade("KintoWalletFactory", "V8", bytecode);

        // // upgrade SponsorPaymaster to V5
        // bytecode = abi.encodePacked(type(SponsorPaymaster).creationCode, abi.encode(_getChainDeployment("EntryPoint")));
        // deployAndUpgrade("SponsorPaymaster", "V5", bytecode);

        // // Initialize paymaster
        // SponsorPaymaster paymaster = SponsorPaymaster(_getChainDeployment("SponsorPaymaster"));
        // // Set up variables
        // vm.broadcast();
        // paymaster.setUserOpMaxCost(3e16);

        // // upgrade KintoID to V6
        // bytecode = abi.encodePacked(type(KintoID).creationCode, abi.encode(""));
        // deployAndUpgrade("KintoID", "V6", bytecode);

        // KintoID _id = KintoID(_getChainDeployment("KintoID"));
        // vm.broadcast();
        // _id.initializeV6();
        // require(_id.domainSeparator() != bytes32(0), "KintoID domain separator not initialized");

        // // upgrade SponsorPaymaster to V6
        //  bytecode = abi.encodePacked(type(SponsorPaymaster).creationCode, abi.encode(_getChainDeployment("EntryPoint")));
        // deployAndUpgrade("SponsorPaymaster", "V6", bytecode);
        // vm.broadcast();
        // paymaster.initializeV6(_getChainDeployment("KintoID"));
        // require(address(paymaster.kintoID()) != address(0), "SponsorPaymaster kintoID not initialized");
        // vm.broadcast();
        // paymaster.addDepositFor{value: 5e16}(_getChainDeployment("KYCViewer"));

        // Initialize KYCViewer
        // address payable _from = payable(_getChainDeployment("KintoWallet-admin"));

        // // prep upgradeTo user op
        // uint256 nonce = IKintoWallet(_from).getNonce();
        // uint256[] memory privateKeys = new uint256[](1);
        // privateKeys[0] = vm.envUint("PRIVATE_KEY");
        // UserOperation[] memory userOps = new UserOperation[](2);

        // address[] memory apps = new address[](1);
        // apps[0] = address(_getChainDeployment("KYCViewer"));

        // bool[] memory flags = new bool[](1);
        // flags[0] = true;

        // userOps[0] = _createUserOperation(
        //     block.chainid,
        //     _from,
        //     _from,
        //     0,
        //     nonce,
        //     privateKeys,
        //     abi.encodeWithSelector(IKintoWallet.whitelistApp.selector, apps, flags),
        //     _getChainDeployment("SponsorPaymaster")
        // );

        // userOps[1] = _createUserOperation(
        //     block.chainid,
        //     _from,
        //     _getChainDeployment("KYCViewer"),
        //     0,
        //     nonce + 1,
        //     privateKeys,
        //     abi.encodeWithSelector(KYCViewer.initialize.selector),
        //     _getChainDeployment("SponsorPaymaster")
        // );

        // vm.broadcast(deployerPrivateKey);
        // IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(privateKeys[0])));

        // _transferOwnership(_getChainDeployment("KYCViewer"), vm.envUint("PRIVATE_KEY"), vm.envAddress("LEDGER_ADMIN"));

        // upgrade KYCViewer to V3
        // KYCViewer viewer = KYCViewer(_getChainDeployment("KYCViewer"));
        // bytes memory bytecode = abi.encodePacked(
        //     type(KYCViewer).creationCode,
        //     abi.encode(_getChainDeployment("KintoWalletFactory"), _getChainDeployment("Faucet"))
        // );

        // deployAndUpgrade("KYCViewer", "V3", bytecode);
        // console.log(KintoAppRegistry(_getChainDeployment("KintoAppRegistry")).owner());
    }
}

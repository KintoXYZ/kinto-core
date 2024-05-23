// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "../../src/tokens/EngenCredits.sol";
import "../../src/wallet/KintoWallet.sol";
import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/interfaces/IKintoWallet.sol";
import "../../src/bridger/BridgerL2.sol";
import "../../src/bridger/Bridger.sol";

import "@kinto-core-script/utils/MigrationHelper.sol";

interface ISocketBridger {
    function bridge(
        address receiver_,
        uint256 amount_,
        uint256 msgGasLimit_,
        address connector_,
        bytes calldata execPayload_,
        bytes calldata options_
    ) external payable;
}

contract KintoMigration71DeployScript is MigrationHelper {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();
        // KintoWalletFactory factory = KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));
        KintoWallet wallet = KintoWallet(payable(_getChainDeployment("KintoWallet-admin")));
        
        vm.prank(address(wallet));
        address[] memory signers = new address[](1);
        signers[0] = 0x660ad4B5A74130a4796B4d54BC6750Ae93C86e6c;
        wallet.resetSigners(signers, 1);

        address receiver = wallet.owners(0);
        uint256 amount = 0.0001 ether;
        uint256 gasLimit = 0;
        // 0xaBc64E84c653e0f077c0178E4b1fAC01Bfcc20b0 dai controller
        // 0xe1BE0bB38818b2cAa1B1a188496952daDe261A40 dai connector

        // 0xC7FCA8aB6D1E1142790454e7e5655d93c3b03ed6 weeth controller
        // 0x3301d0616365F55a54059707e49F93D18159f129 weeth connector
        ISocketBridger controller = ISocketBridger(0xC7FCA8aB6D1E1142790454e7e5655d93c3b03ed6);
        address connectorAddr = 0x3301d0616365F55a54059707e49F93D18159f129;

        bytes memory payload = "0x";
        bytes memory options = "0x";

        bytes memory selectorAndParams = abi.encodeWithSelector(ISocketBridger.bridge.selector, receiver, amount, gasLimit, connectorAddr, payload, options);
        _handleOps(selectorAndParams, address(wallet), address(controller), 0.1 ether, address(0), deployerPrivateKey);

    }
}

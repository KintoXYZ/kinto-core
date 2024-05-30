// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@kinto-core/tokens/EngenBadges.sol";
import "@kinto-core/interfaces/IKintoWallet.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "@kinto-core-script/utils/MigrationHelper.sol";

import "@kinto-core-script/migrations/const.sol";

contract MintEngenBadgesScript is MigrationHelper, Constants {
    using ECDSAUpgradeable for bytes32;

    function run() public override {
        super.run();

        address engenBadgesAddr = _getChainDeployment("EngenBadges");
        IKintoWallet adminWallet = IKintoWallet(_getChainDeployment("KintoWallet-admin"));

        etchWallet();
        // replaceOwner(adminWallet, 0x4632F4120DC68F225e7d24d973Ee57478389e9Fd);
        // replaceOwner(adminWallet, _getChainDeployment("EntryPoint"));

        uint256[] memory ids = new uint256[](1);
        ids[0] = 42;

        uint256[] memory privKeys = new uint256[](2);
        privKeys[0] = deployerPrivateKey;
        privKeys[1] = LEDGER;
        _handleOps(
            abi.encodeWithSelector(EngenBadges.mintBadges.selector, address(adminWallet), ids),
            address(adminWallet),
            engenBadgesAddr,
            address(0),
            privKeys
        );
    }

    function etchWallet() internal {
        KintoWallet impl = new KintoWallet(
            IEntryPoint(_getChainDeployment("EntryPoint")),
            IKintoID(_getChainDeployment("KintoID")),
            IKintoAppRegistry(_getChainDeployment("KintoAppRegistry"))
        );
        vm.etch(0xa7040b6Ed2fC09C7485AA6A89fb2C320E2A739c3, address(impl).code);
    }

    function replaceOwner(IKintoWallet wallet, address newOwner) internal {
        address[] memory owners = new address[](3);
        owners[0] = wallet.owners(0);
        owners[1] = newOwner;
        owners[2] = wallet.owners(2);

        uint8 policy = wallet.signerPolicy();
        vm.prank(address(wallet));
        wallet.resetSigners(owners, policy);

        require(wallet.owners(1) == newOwner, "Failed to replace signer");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/paymasters/SponsorPaymaster.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UUPSProxy.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoMigration11DeployScript is Create2Helper, ArtifactsReader {
    using ECDSAUpgradeable for bytes32;

    SponsorPaymaster _paymaster;
    KintoWalletFactory _walletFactory;
    SponsorPaymasterV3 _paymasterImpl;
    UUPSProxy _proxy;

    function setUp() public {}

    // NOTE: this migration must be run from the ledger admin
    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));

        // execute this script with the with the ledger
        console.log("Executing from address", msg.sender);

        address sponsorAddr = _getChainDeployment("SponsorPaymaster");
        if (sponsorAddr == address(0)) {
            console.log("Need to execute main deploy script first", sponsorAddr);
            return;
        }
        _paymaster = SponsorPaymaster(payable(sponsorAddr));

        _walletFactory = KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));
        bytes memory bytecode =
            abi.encodePacked(type(SponsorPaymasterV3).creationCode, abi.encode(_getChainDeployment("EntryPoint")));

        // deploy new paymaster implementation
        vm.broadcast();
        _paymasterImpl = SponsorPaymasterV3(payable(_walletFactory.deployContract(msg.sender, 0, bytecode, bytes32(0))));

        // this is an admin call, needs to be done to upgrade (impersonate as it's a ledger address)
        require(msg.sender == _paymaster.owner(), "Only owner can upgrade");
        vm.broadcast();
        _paymaster.upgradeTo(address(_paymasterImpl));

        // sanity check: paymaster's cost of op should be 200_000
        require(_paymaster.COST_OF_POST() == 200_000, "COST_OF_POST should be 200_000");

        // writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"SponsorPaymasterV3-impl": "', vm.toString(address(_paymasterImpl)), '"'));
    }
}

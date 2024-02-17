// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/wallet/KintoWallet.sol";
import "../../src/paymasters/SponsorPaymaster.sol";
import "../../src/KintoID.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UUPSProxy.sol";
import "./utils/MigrationHelper.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoIDV3 is KintoID {
    constructor(address _walletFactory) KintoID(_walletFactory) {}
}

contract KintoMigration13DeployScript is Create2Helper, ArtifactsReader {
    using MessageHashUtils for bytes32;

    KintoWalletFactory _walletFactory;
    SponsorPaymaster _paymaster;
    SponsorPaymasterV3 _paymasterImpl;
    KintoID _kintoID;
    KintoIDV3 _kintoIDImpl;
    UUPSProxy _proxy;

    function setUp() public {}

    // NOTE: this migration must be run from the ledger admin
    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // execute this script with the with the ledger
        console.log("Executing from address", msg.sender);

        // get wallet factory
        _walletFactory = KintoWalletFactory(payable(_getChainDeployment("KintoWalletFactory")));

        // (1). deploy new paymaster implementation via wallet factory
        address sponsorAddr = _getChainDeployment("SponsorPaymaster");
        if (sponsorAddr == address(0)) {
            console.log("Need to execute main deploy script first", sponsorAddr);
            return;
        }
        _paymaster = SponsorPaymaster(payable(sponsorAddr));
        bytes memory bytecode =
            abi.encodePacked(type(SponsorPaymasterV3).creationCode, abi.encode(_getChainDeployment("EntryPoint")));
        console.log("factory", address(_walletFactory));
        _paymasterImpl = SponsorPaymasterV3(payable(_walletFactory.deployContract(msg.sender, 0, bytecode, bytes32(0))));

        // (2). deploy new kinto ID implementation via wallet factory
        address kintoIDAddr = _getChainDeployment("KintoID");
        if (kintoIDAddr == address(0)) {
            console.log("Need to execute main deploy script first", kintoIDAddr);
            return;
        }
        _kintoID = KintoID(payable(kintoIDAddr));
        bytecode = abi.encodePacked(type(KintoIDV3).creationCode, abi.encode(_getChainDeployment("KintoWalletFactory")));
        _kintoIDImpl = KintoIDV3(payable(_walletFactory.deployContract(msg.sender, 0, bytecode, bytes32(0))));

        vm.stopBroadcast();
        vm.startBroadcast();
        // (3). upgrade paymaster to new implementation
        Upgradeable(address(_paymaster)).upgradeTo(address(_paymasterImpl));

        // sanity check: paymaster's cost of op should be 200_000
        require(_paymaster.COST_OF_POST() == 200_000, "COST_OF_POST should be 200_000");

        // (4). upgrade kinto id to new implementation
        // vm.prank(_paymaster.owner());
        Upgradeable(address(_kintoID)).upgradeTo(address(_kintoIDImpl));

        // sanity check: paymaster's cost of op should be 200_000
        try _kintoID.burn(10) {
            revert("should have reverted");
        } catch Error(string memory reason) {
            require(
                keccak256(abi.encodePacked(reason)) == keccak256(abi.encodePacked("Use burnKYC instead")),
                "Incorrect error reason"
            );
        }
        vm.stopBroadcast();
        // writes the addresses to a file
        console.log("Add these new addresses to the artifacts file");
        console.log(string.concat('"SponsorPaymasterV3-impl": "', vm.toString(address(_paymasterImpl)), '"'));
        console.log(string.concat('"KintoIDV3-impl": "', vm.toString(address(_kintoIDImpl)), '"'));
    }
}

contract SponsorPaymasterV3 is SponsorPaymaster {
    constructor(IEntryPoint __entryPoint) SponsorPaymaster(__entryPoint) {}
}

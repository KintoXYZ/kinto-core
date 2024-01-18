// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UserOp.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoMigration18DeployScript is Create2Helper, ArtifactsReader, UserOp {
    using ECDSAUpgradeable for bytes32;

    function setUp() public {}

    function run() public {
        console.log("Chain ID", vm.toString(block.chainid));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        console.log("Deployer address: ", vm.addr(deployerPrivateKey));

        _execute(deployerPrivateKey);
    }

    function _execute(uint256 _signerPk) internal {
        address _from = 0x58Dd6931DC95292F2E78Cf195a7FC30868Be8aFd;
        uint256 _nonce = IKintoWallet(_from).getNonce();
        bytes memory _encodedData =
            "0xb61d27f600000000000000000000000058dd6931dc95292f2e78cf195a7fc30868be8afd0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000c4ca85f3340000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000030000000000000000000000000c1df30b4576a1a94d9528854516d4d425cf9323000000000000000000000000660ad4b5a74130a4796b4d54bc6750ae93c86e6c0000000000000000000000006fe642404b7b23f31251103ca0efb538ad4aec0700000000000000000000000000000000000000000000000000000000";

        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = _signerPk;

        address walletOwner = IKintoWallet(_from).owners(0);
        console.log("Owner", walletOwner);

        UserOperation[] memory userOps = new UserOperation[](1);
        // userOps[0] = UserOperation({
        //     sender: _from,
        //     nonce: _nonce,
        //     initCode: bytes(""),
        //     callData: _encodedData,
        //     callGasLimit: 0x7a1200, // generate from call simulation
        //     verificationGasLimit: 0x38270, // verification gas. will add create2 cost (3200+200*length) if initCode exists
        //     preVerificationGas: 0x9c40, // should also cover calldata cost.
        //     maxFeePerGas: 0x6dac2c0, // grab from current gas
        //     maxPriorityFeePerGas: 0x6dac2c0, // grab from current gas
        //     paymasterAndData: abi.encodePacked(_getChainDeployment("SponsorPaymaster")),
        //     signature: "0x85982573ef949b5d4b0814f963a2c3929459a4f88ceda2dc7b3a5cee417e1d9b75022db618eee034d2047f84c4d246fe677e6e16b9d23c9ff93610ee99462b0b1c"
        // });

        address[] memory owners = new address[](2);
        owners[0] = 0x0C1df30B4576A1A94D9528854516D4d425Cf9323;
        owners[1] = 0x660ad4B5A74130a4796B4d54BC6750Ae93C86e6c;
        owners[1] = 0x6fe642404B7B23F31251103Ca0efb538Ad4aeC07;

        userOps[0] = _createUserOperation(
            address(_from),
            address(_from),
            _nonce,
            privateKeys,
            abi.encodeWithSignature("resetSigners(address[],uint8)", owners, 2),
            0x1842a4EFf3eFd24c50B63c3CF89cECEe245Fc2bd
        );
        userOps[0].signature = "0x85982573ef949b5d4b0814f963a2c3929459a4f88ceda2dc7b3a5cee417e1d9b75022db618eee034d2047f84c4d246fe677e6e16b9d23c9ff93610ee99462b0b1c";

        // bytes4 selector = bytes4(_encodedData[:4]); // function selector
        console.log("0xb61d27f6");
        bytes memory selector = abi.encodeWithSelector(IKintoWallet.execute.selector);
        console.logBytes(selector);
        // [
        //     {
        //         "sender": "0x58Dd6931DC95292F2E78Cf195a7FC30868Be8aFd",
        //         "nonce": "0x0",
        //         "initCode": "0x",
        //         "callData": "0xb61d27f600000000000000000000000058dd6931dc95292f2e78cf195a7fc30868be8afd0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000c4ca85f3340000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000030000000000000000000000000c1df30b4576a1a94d9528854516d4d425cf9323000000000000000000000000660ad4b5a74130a4796b4d54bc6750ae93c86e6c0000000000000000000000006fe642404b7b23f31251103ca0efb538ad4aec0700000000000000000000000000000000000000000000000000000000",
        //         "paymasterAndData": "0x1842a4eff3efd24c50b63c3cf89cecee245fc2bd",
        //         "signature": "0x85982573ef949b5d4b0814f963a2c3929459a4f88ceda2dc7b3a5cee417e1d9b75022db618eee034d2047f84c4d246fe677e6e16b9d23c9ff93610ee99462b0b1c",
        //         "maxFeePerGas": "0x6dac2c0",
        //         "maxPriorityFeePerGas": "0x6dac2c0",
        //         "callGasLimit": "0x7a1200",
        //         "verificationGasLimit": "0x38270",
        //         "preVerificationGas": "0x9c40"
        //     },
        //     "0x2843C269D2a64eCfA63548E8B3Fc0FD23B7F70cb"
        // ]

        // execute op via entry point
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(_signerPk)));
    }
}

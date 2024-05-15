// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../../src/KintoID.sol";
import "../../src/wallet/KintoWallet.sol";
import "../../src/wallet/KintoWalletFactory.sol";
import "../../src/tokens/EngenCredits.sol";
import "../../src/apps/KintoAppRegistry.sol";
import "../../src/paymasters/SponsorPaymaster.sol";

import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UUPSProxy.sol";
import "../../test/helpers/UserOp.sol";

contract KintoMigration12DeployScript is ArtifactsReader, UserOp {
    KintoWalletFactory _walletFactory;
    KintoWallet _kintoWalletv1;
    KintoID _kintoID;
    UUPSProxy _proxy;

    function setUp() public {}

    // solhint-disable code-complexity
    function run() public {
        console.log("RUNNING ON CHAIN WITH ID", vm.toString(block.chainid));

        // call from hot wallet
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.rememberKey(deployerPrivateKey);
        console.log("Executing from address", deployer);

        // sanity check: main deployed has run
        address walletFactoryAddr = _getChainDeployment("KintoWalletFactory");
        if (walletFactoryAddr == address(0)) {
            console.log("Need to execute main deploy script first", walletFactoryAddr);
            return;
        }

        // contracts
        KintoAppRegistry _kintoAppRegistry = KintoAppRegistry(_getChainDeployment("KintoAppRegistry"));
        IKintoWallet _kintoWallet = IKintoWallet(_getChainDeployment("KintoWallet-admin"));
        IEntryPoint _entryPoint = IEntryPoint(_getChainDeployment("EntryPoint"));
        EngenCredits _credits = EngenCredits(_getChainDeployment("EngenCredits"));
        SponsorPaymaster _paymaster = SponsorPaymaster(_getChainDeployment("SponsorPaymaster"));

        // fund KintoWallet in the paymaster
        vm.broadcast(deployerPrivateKey);
        _paymaster.addDepositFor{value: 0.1 ether}(address(_kintoWallet));
        assertEq(_paymaster.balances(address(_kintoWallet)), 0.1 ether);

        // fund KintoAppRegistry in the paymaster
        vm.broadcast(deployerPrivateKey);
        _paymaster.addDepositFor{value: 0.1 ether}(address(_kintoAppRegistry));
        assertEq(_paymaster.balances(address(_kintoAppRegistry)), 0.1 ether);

        console.log("KintoWallet funds:", _paymaster.balances(address(_kintoWallet)));
        console.log("Engen Credits funds:", _paymaster.balances(address(_credits)));
        console.log("Registry funds:", _paymaster.balances(address(_kintoAppRegistry)));

        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = deployerPrivateKey;
        uint256 nonce = _kintoWallet.getNonce();

        UserOperation[] memory userOps = new UserOperation[](3);

        // whitelist Engen Credits & Registry
        address[] memory apps = new address[](2);
        apps[0] = address(_credits);
        apps[1] = address(_kintoAppRegistry);

        bool[] memory flags = new bool[](2);
        flags[0] = true;
        flags[1] = true;

        userOps[0] = _createUserOperation(
            block.chainid,
            address(_kintoWallet),
            address(_kintoWallet),
            0,
            nonce,
            privateKeys,
            abi.encodeWithSelector(IKintoWallet.whitelistApp.selector, apps, flags),
            address(_paymaster)
        );

        // call initialise on KintoRegistryApp
        userOps[1] = _createUserOperation(
            block.chainid,
            address(_kintoWallet),
            address(_kintoAppRegistry),
            0,
            nonce + 1,
            privateKeys,
            abi.encodeWithSelector(KintoAppRegistry.initialize.selector),
            address(_paymaster)
        );

        // register Engen Credits app into the registry
        userOps[2] = _createUserOperation(
            block.chainid,
            address(_kintoWallet),
            address(_kintoAppRegistry),
            0,
            nonce + 2,
            privateKeys,
            abi.encodeWithSignature(
                "registerApp(string,address,address[],uint256[4])",
                "Engen",
                address(_credits),
                new address[](0),
                [uint256(0), uint256(0), uint256(0), uint256(0)]
            ),
            address(_paymaster)
        );

        // execute transaction via entry point & broadcast
        vm.broadcast(deployerPrivateKey);
        _entryPoint.handleOps(userOps, payable(deployer));

        // sanity checks:

        // (1). app is whitelisted
        assertTrue(_kintoWallet.appWhitelist(address(_credits)));

        // // (2). initialising the Engen Credits should revert because it's has already been initialised
        vm.expectRevert();
        _credits.initialize();

        // // (3). Engen Credits is registered in the registry
        IKintoAppRegistry.Metadata memory metadata = _kintoAppRegistry.getAppMetadata(address(_credits));
        assertEq(metadata.name, "Engen");

        console.log("Engen APP created and minted");
    }
}

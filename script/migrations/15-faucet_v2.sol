// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../src/interfaces/IKintoWalletFactory.sol";
import "../../src/interfaces/IKintoWallet.sol";
import "../../src/interfaces/ISponsorPaymaster.sol";

import "../../src/Faucet.sol";

import "../../test/helpers/Create2Helper.sol";
import "../../test/helpers/ArtifactsReader.sol";
import "../../test/helpers/UUPSProxy.sol";
import "../../test/helpers/UserOp.sol";

import "forge-std/Script.sol";
import "forge-std/console.sol";

contract KintoMigration15DeployScript is Create2Helper, ArtifactsReader, UserOp {
    using ECDSAUpgradeable for bytes32;

    Faucet _implementation;
    UUPSProxy _proxy;

    function setUp() public {}

    function run() public {
        console.log("Chain ID", vm.toString(block.chainid));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        console.log("Deployer address: ", vm.addr(deployerPrivateKey));

        vm.startBroadcast(deployerPrivateKey);

        // make sure faucet proxy is not already deployed
        address faucetProxy = payable(_getChainDeployment("Faucet"));
        require(faucetProxy == address(0), "Faucet proxy is already deployed");

        // make sure wallet factory is deployed
        address factory = _getChainDeployment("KintoWalletFactory");
        require(factory != address(0), "Need to deploy the wallet factory first");

        // use wallet factory to deploy Faucet implementation & proxy
        IKintoWalletFactory walletFactory = IKintoWalletFactory(payable(factory));
        address payable adminWallet = payable(_getChainDeployment("KintoWallet-admin"));

        // (1). deploy Faucet implementation
        bytes memory bytecode = abi.encodePacked(type(Faucet).creationCode, abi.encode(factory));
        _implementation = Faucet(payable(walletFactory.deployContract(msg.sender, 0, bytecode, bytes32(0))));

        // (2). deploy Faucet proxy
        bytecode = abi.encodePacked(type(UUPSProxy).creationCode, abi.encode(address(_implementation), ""));
        _proxy = UUPSProxy(payable(walletFactory.deployContract(msg.sender, 0, bytecode, bytes32(0))));

        // (3). fund Kinto wallet with 1 ether from deployer
        walletFactory.fundWallet{value: 1 ether}(adminWallet);

        // (4). execute user ops (whitelist faucet on KintoWallet, initialise and startFaucet on Faucet)
        _execute(adminWallet, address(_proxy), deployerPrivateKey);

        vm.stopBroadcast();

        // sanity checks:
        require(Faucet(payable(address(_proxy))).active(), "Faucet is not active");
        require(Faucet(payable(address(_proxy))).CLAIM_AMOUNT() == 1 ether / 2500, "Claim amount is not correct");

        // Writes the addresses to a file
        console.log(string.concat("Faucet-impl: ", vm.toString(address(_implementation))));
        console.log(string.concat("Faucet: ", vm.toString(address(_proxy))));
    }

    function _execute(address _from, address _faucet, uint256 _signerPk) internal {
        // fund Faucet in the paymaster
        ISponsorPaymaster _paymaster = ISponsorPaymaster(_getChainDeployment("SponsorPaymaster"));
        _paymaster.addDepositFor{value: 0.1 ether}(address(address(_faucet)));
        assertEq(_paymaster.balances(address(_proxy)), 0.1 ether);

        // prep user ops
        uint256 nonce = IKintoWallet(_from).getNonce();
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = _signerPk;
        UserOperation[] memory userOps = new UserOperation[](3);

        {
            // (1). whitelist faucet
            address[] memory apps = new address[](1);
            apps[0] = address(_faucet);

            bool[] memory flags = new bool[](1);
            flags[0] = true;

            userOps[0] = this.createUserOperation(
                block.chainid,
                _from,
                nonce,
                privateKeys,
                _from,
                0,
                abi.encodeWithSelector(IKintoWallet.whitelistApp.selector, apps, flags),
                _getChainDeployment("SponsorPaymaster")
            );
        }

        // (2). initialise faucet
        userOps[1] = this.createUserOperation(
            block.chainid,
            _from,
            nonce + 1,
            privateKeys,
            _faucet,
            0,
            abi.encodeWithSelector(Faucet.initialize.selector),
            _getChainDeployment("SponsorPaymaster")
        );

        // (3). call startFaucet
        userOps[2] = this.createUserOperation(
            block.chainid,
            _from,
            nonce + 2,
            privateKeys,
            _faucet,
            1 ether,
            abi.encodeWithSelector(Faucet.startFaucet.selector),
            _getChainDeployment("SponsorPaymaster")
        );

        // execute transaction via entry point & broadcast
        IEntryPoint(_getChainDeployment("EntryPoint")).handleOps(userOps, payable(vm.addr(_signerPk)));
    }
}

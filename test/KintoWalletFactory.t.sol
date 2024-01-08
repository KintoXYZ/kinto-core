// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/wallet/KintoWallet.sol";
import "../src/wallet/KintoWalletFactory.sol";
import "../src/paymasters/SponsorPaymaster.sol";
import "../src/KintoID.sol";
import {UserOp} from "./helpers/UserOp.sol";
import {UUPSProxy} from "./helpers/UUPSProxy.sol";
import {AATestScaffolding} from "./helpers/AATestScaffolding.sol";
import {Create2Helper} from "./helpers/Create2Helper.sol";
import "../src/sample/Counter.sol";

import "@aa/interfaces/IAccount.sol";
import "@aa/interfaces/INonceManager.sol";
import "@aa/interfaces/IEntryPoint.sol";
import "@aa/core/EntryPoint.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract KintoWalletV999 is KintoWallet {
    constructor(IEntryPoint _entryPoint, IKintoID _kintoID, IKintoAppRegistry _kintoApp)
        KintoWallet(_entryPoint, _kintoID, _kintoApp)
    {}

    function walletFunction() public pure returns (uint256) {
        return 1;
    }
}

contract KintoWalletFactoryV999 is KintoWalletFactory {
    constructor(KintoWallet _impl) KintoWalletFactory(_impl) {}

    function newFunction() public pure returns (uint256) {
        return 1;
    }
}

contract KintoWalletFactoryTest is Create2Helper, UserOp, AATestScaffolding {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    KintoWalletFactoryV999 _walletFactoryv2;
    KintoWalletV999 _kintoWalletv2;

    uint256 _chainID = 1;

    function setUp() public {
        vm.chainId(_chainID);
        vm.startPrank(address(1));
        _owner.transfer(1e18);
        vm.stopPrank();
        deployAAScaffolding(_owner, 1, _kycProvider, _recoverer);
    }

    function testUp() public {
        assertEq(_walletFactory.factoryWalletVersion(), 1);
        assertEq(_entryPoint.walletFactory(), address(_walletFactory));
    }

    /* ============ Upgrade Tests ============ */

    function testOwnerCanUpgradeFactory() public {
        vm.startPrank(_owner);
        KintoWalletFactoryV999 _implementationV999 = new KintoWalletFactoryV999(_kintoWalletImpl);
        _walletFactory.upgradeTo(address(_implementationV999));
        // re-wrap the _proxy
        _walletFactoryv2 = KintoWalletFactoryV999(address(_walletFactory));
        assertEq(_walletFactoryv2.newFunction(), 1);
        vm.stopPrank();
    }

    function test_RevertWhen_OthersCannotUpgradeFactory() public {
        KintoWalletFactoryV999 _implementationV999 = new KintoWalletFactoryV999(_kintoWalletImpl);
        vm.expectRevert("Ownable: caller is not the owner");
        _walletFactory.upgradeTo(address(_implementationV999));
    }

    function testAllWalletsUpgrade() public {
        vm.startPrank(_owner);

        // Deploy wallet implementation
        _kintoWalletImpl = new KintoWalletV999(_entryPoint, _kintoIDv1, _kintoApp);

        // deploy walletv1 through wallet factory and initializes it
        _kintoWalletv1 = _walletFactory.createAccount(_owner, _owner, 0);

        // Upgrade all implementations
        _walletFactory.upgradeAllWalletImplementations(_kintoWalletImpl);

        KintoWalletV999 walletV2 = KintoWalletV999(payable(address(_kintoWalletv1)));
        assertEq(walletV2.walletFunction(), 1);
        vm.stopPrank();
    }

    function testUpgrade_RevertWhen_CallerIsNotOwner() public {
        // deploy wallet implementation
        _kintoWalletImpl = new KintoWalletV999(_entryPoint, _kintoIDv1, _kintoApp);

        // deploy walletv1 through wallet factory and initializes it
        _kintoWalletv1 = _walletFactory.createAccount(_owner, _owner, 0);

        // upgrade all implementations
        vm.expectRevert("Ownable: caller is not the owner");
        _walletFactory.upgradeAllWalletImplementations(_kintoWalletImpl);
    }

    /* ============ Deploy Tests ============ */
    function testDeployCustomContract() public {
        vm.startPrank(_owner);
        address computed =
            _walletFactory.getContractAddress(bytes32(0), keccak256(abi.encodePacked(type(Counter).creationCode)));
        address created =
            _walletFactory.deployContract(_owner, 0, abi.encodePacked(type(Counter).creationCode), bytes32(0));
        assertEq(computed, created);
        assertEq(Counter(created).count(), 0);
        Counter(created).increment();
        assertEq(Counter(created).count(), 1);
        vm.stopPrank();
    }

    function testDeploy_RevertWhen_CreateWalletThroughDeploy() public {
        vm.startPrank(_owner);
        bytes memory initialize = abi.encodeWithSelector(KintoWallet.initialize.selector, _owner, _owner);
        bytes memory bytecode = abi.encodePacked(
            type(SafeBeaconProxy).creationCode, abi.encode(address(_walletFactory.beacon()), initialize)
        );
        vm.expectRevert("Direct KintoWallet deployment not allowed");
        _walletFactory.deployContract(_owner, 0, bytecode, bytes32(0));
        vm.stopPrank();
    }

    function testSignerCanFundWallet() public {
        vm.startPrank(_owner);
        _walletFactory.fundWallet{value: 1e18}(payable(address(_kintoWalletv1)));
        assertEq(address(_kintoWalletv1).balance, 1e18);
    }

    function testWhitelistedSignerCanFundWallet() public {
        vm.startPrank(_owner);
        _fundPaymasterForContract(address(_kintoWalletv1));
        uint256 startingNonce = _kintoWalletv1.getNonce();
        address[] memory funders = new address[](1);
        funders[0] = _funder;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        uint256[] memory privateKeys = new uint256[](1);
        privateKeys[0] = 1;
        UserOperation memory userOp = this.createUserOperationWithPaymaster(
            _chainID,
            address(_kintoWalletv1),
            startingNonce,
            privateKeys,
            address(_kintoWalletv1),
            0,
            abi.encodeWithSignature("setFunderWhitelist(address[],bool[])", funders, flags),
            address(_paymaster)
        );
        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;
        // Execute the transaction via the entry point
        _entryPoint.handleOps(userOps, payable(_owner));
        vm.startPrank(address(1));
        _funder.transfer(1e17);
        vm.stopPrank();
        vm.startPrank(_funder);
        _walletFactory.fundWallet{value: 1e17}(payable(address(_kintoWalletv1)));
        assertEq(address(_kintoWalletv1).balance, 1e17);
    }

    function testSignerCannotFundInvalidWallet() public {
        vm.startPrank(_owner);
        vm.expectRevert("Invalid wallet or funder");
        _walletFactory.fundWallet{value: 1e18}(payable(address(0)));
    }

    function testRandomSignerCannotFundWallet() public {
        vm.startPrank(address(1));
        _user.transfer(1e18);
        vm.stopPrank();
        vm.startPrank(_user);
        vm.expectRevert("Invalid wallet or funder");
        _walletFactory.fundWallet{value: 1e18}(payable(address(_kintoWalletv1)));
    }

    function testSignerCannotFundWalletWithoutEth() public {
        vm.startPrank(_owner);
        vm.expectRevert("Invalid wallet or funder");
        _walletFactory.fundWallet{value: 0}(payable(address(_kintoWalletv1)));
    }
}

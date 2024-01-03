// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "../src/wallet/KintoWallet.sol";
import "../src/wallet/KintoWalletFactory.sol";
import "../src/paymasters/SponsorPaymaster.sol";
import "../src/KintoID.sol";
import "../src/viewers/KYCViewer.sol";
import {UserOp} from "./helpers/UserOp.sol";
import {UUPSProxy} from "./helpers/UUPSProxy.sol";
import {AATestScaffolding} from "./helpers/AATestScaffolding.sol";
import {Create2Helper} from "./helpers/Create2Helper.sol";
import "./helpers/KYCSignature.sol";

import "@aa/interfaces/IAccount.sol";
import "@aa/interfaces/INonceManager.sol";
import "@aa/interfaces/IEntryPoint.sol";
import "@aa/core/EntryPoint.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract Counter is Ownable {
    uint256 public count = 0;

    constructor() Ownable() {}

    function increment() public onlyOwner {
        count += 1;
    }
}

contract CounterInitializable is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        __Ownable_init();
        _transferOwnership(initialOwner);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

contract DeveloperDeployTest is Create2Helper, UserOp, AATestScaffolding {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;

    uint256 _chainID = 1;

    address payable _owner = payable(vm.addr(1));
    address _secondowner = address(2);
    address payable _user = payable(vm.addr(3));
    address _user2 = address(4);
    address _upgrader = address(5);
    address _kycProvider = address(6);
    address _recoverer = address(7);
    address payable _funder = payable(vm.addr(8));

    UUPSProxy _proxyc;
    Counter _counter;
    CounterInitializable _counterInit;

    function setUp() public {
        vm.chainId(_chainID);
        vm.startPrank(address(1));
        _owner.transfer(1e18);
        vm.stopPrank();
        deployAAScaffolding(_owner, _kycProvider, _recoverer);
        vm.startPrank(_owner);

        address created = _walletFactory.deployContract(_owner, 0, abi.encodePacked(type(Counter).creationCode), bytes32(0));
        _counter = Counter(created);

        created =
            _walletFactory.deployContract(_owner, 0, abi.encodePacked(type(CounterInitializable).creationCode), bytes32(0));

        // deploy _proxy contract and point it to _implementation
        _proxyc = new UUPSProxy{salt: 0}(address(created), "");
        // wrap in ABI to support easier calls
        _counterInit = CounterInitializable(address(_proxyc));
        // Initialize proxy
        _counterInit.initialize(_user2);
        vm.stopPrank();
    }

    function testUp() public {
        assertEq(address(_owner), _counter.owner());
        assertEq(_user2, _counterInit.owner());
    }
}

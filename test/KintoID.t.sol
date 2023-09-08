// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import '../src/KintoID.sol';
import '../src/interfaces/IKintoID.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol';
import {SignatureChecker} from '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';

import 'forge-std/Test.sol';
import 'forge-std/console.sol';

contract UUPSProxy is ERC1967Proxy {
    constructor(address __implementation, bytes memory _data)
        ERC1967Proxy(__implementation, _data)
    {}
}

contract KintoIDv2 is KintoID {
  constructor() KintoID() {

  }
  function newFunction() public pure returns (uint256) {
      return 1;
  }
}

contract KintoIDTest is Test {
    using ECDSAUpgradeable for bytes32;
    using SignatureChecker for address;
    KintoID _implementation;

    KintoID _kintoIDv1;
    KintoIDv2 _kintoIDv2;
    UUPSProxy _proxy;

    address _owner = address(1);
    address _kycProvider = address(2);
    address _user = vm.addr(3);
    address _user2 = address(4);
    address _upgrader = address(5);

    function setUp() public {
        vm.chainId(1);
        vm.startPrank(_owner);
        _implementation = new KintoID();
        // deploy _proxy contract and point it to _implementation
        _proxy = new UUPSProxy(address(_implementation), '');
        // wrap in ABI to support easier calls
        _kintoIDv1 = KintoID(address(_proxy));
        // Initialize _proxy
        _kintoIDv1.initialize();
        _kintoIDv1.grantRole(_kintoIDv1.KYC_PROVIDER_ROLE(), _kycProvider);
        vm.stopPrank();
    }

    function testUp() public {
        assertEq(_kintoIDv1.lastMonitoredAt(), block.timestamp);
        assertEq(_kintoIDv1.name(), 'Kinto ID');
        assertEq(_kintoIDv1.symbol(), 'KINID');
        assertEq(_kintoIDv1.KYC_TOKEN_ID(), 1);
    }

    // Upgrade Tests

    function testOwnerCanUpgrade() public {
        vm.startPrank(_owner);
        KintoIDv2 _implementationV2 = new KintoIDv2();
        _kintoIDv1.upgradeTo(address(_implementationV2));
        // re-wrap the _proxy
        _kintoIDv2 = KintoIDv2(address(_proxy));
        assertEq(_kintoIDv2.newFunction(), 1);
        vm.stopPrank();
    }

    function testFailOthersCannotUpgrade() public {
        KintoIDv2 _implementationV2 = new KintoIDv2();
        _kintoIDv1.upgradeTo(address(_implementationV2));
        // re-wrap the _proxy
        _kintoIDv2 = KintoIDv2(address(_proxy));
        assertEq(_kintoIDv2.newFunction(), 1);
    }

    function testAuthorizedCanUpgrade() public {
        assertEq(false, _kintoIDv1.hasRole(_kintoIDv1.UPGRADER_ROLE(), _upgrader));
        vm.startPrank(_owner);
        _kintoIDv1.grantRole(_kintoIDv1.UPGRADER_ROLE(), _upgrader);
        vm.stopPrank();
        // Upgrade from the _upgrader account
        assertEq(true, _kintoIDv1.hasRole(_kintoIDv1.UPGRADER_ROLE(), _upgrader));
        KintoIDv2 _implementationV2 = new KintoIDv2();
        vm.startPrank(_upgrader);
        _kintoIDv1.upgradeTo(address(_implementationV2));
        // re-wrap the _proxy
        _kintoIDv2 = KintoIDv2(address(_proxy));
        vm.stopPrank();
        assertEq(_kintoIDv2.newFunction(), 1);
    }

    // Mint Tests

    function testMintIndividualKYC() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](0);
        vm.startPrank(_kycProvider);
        assertEq(_kintoIDv1.isKYC(_user), false);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        assertEq(_kintoIDv1.isKYC(_user), true);
        assertEq(_kintoIDv1.isIndividual(_user), true);
        assertEq(_kintoIDv1.mintedAt(_user), block.timestamp);
        assertEq(_kintoIDv1.hasTrait(_user, 1), false);
        assertEq(_kintoIDv1.hasTrait(_user, 2), false);
        assertEq(_kintoIDv1.balanceOf(_user, _kintoIDv1.KYC_TOKEN_ID()), 1);
    }

    function testMintCompanyKYC() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](2);
        traits[0] = 2;
        traits[1] = 5;
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintCompanyKyc(sigdata, traits);
        assertEq(_kintoIDv1.isKYC(_user), true);
        assertEq(_kintoIDv1.isCompany(_user), true);
        assertEq(_kintoIDv1.mintedAt(_user), block.timestamp);
        assertEq(_kintoIDv1.hasTrait(_user, 1), false);
        assertEq(_kintoIDv1.hasTrait(_user, 2), true);
        assertEq(_kintoIDv1.hasTrait(_user, 5), true);
        assertEq(_kintoIDv1.balanceOf(_user, _kintoIDv1.KYC_TOKEN_ID()), 1);
    }

    function testMintIndividualKYCWithInvalidSender() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(_user);
        vm.expectRevert('Invalid Provider');
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
    }

    function testMintIndividualKYCWithInvalidSigner() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_user, _user, 5, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(_kycProvider);
        vm.expectRevert('Invalid Signer');
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
    }

    function testMintIndividualKYCWithInvalidNonce() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        vm.expectRevert('Invalid Nonce');
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
    }

    function testMintIndividualKYCWithExpiredSignature() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_user, _user, 3, block.timestamp - 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(_kycProvider);
        vm.expectRevert('Signature has expired');
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
    }

    // Burn Tests

    function testBurnKYC() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        assertEq(_kintoIDv1.isKYC(_user), true);
        sigdata = _auxCreateSignature(_user, _user, 3, block.timestamp + 1000);
        _kintoIDv1.burnKYC(sigdata);
        assertEq(_kintoIDv1.balanceOf(_user, _kintoIDv1.KYC_TOKEN_ID()), 0);
    }

    function testOnlyProviderCanBurnKYC() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        assertEq(_kintoIDv1.isKYC(_user), true);
        sigdata = _auxCreateSignature(_user, _user, 3, block.timestamp + 1000);
        vm.stopPrank();
        vm.startPrank(_user);
        vm.expectRevert('Invalid Provider');
        _kintoIDv1.burnKYC(sigdata);}

    function testBurnFailsWithoutMinting() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_user, _user, 3, block.timestamp + 1000);
        vm.startPrank(_kycProvider);
        vm.expectRevert('Nothing to burn');
        _kintoIDv1.burnKYC(sigdata);
    }

    function testBurningTwiceFails() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(_kycProvider);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        assertEq(_kintoIDv1.isKYC(_user), true);
        sigdata = _auxCreateSignature(_user, _user, 3, block.timestamp + 1000);
        _kintoIDv1.burnKYC(sigdata);
        sigdata = _auxCreateSignature(_user, _user, 3, block.timestamp + 1000);
        vm.expectRevert('Nothing to burn');
        _kintoIDv1.burnKYC(sigdata);
    }

    // Monitor Tests
    function testMonitorNoChanges() public {
        vm.startPrank(_kycProvider);
        _kintoIDv1.monitor(new address[](0), new IKintoID.MonitorUpdateData [][](0));
        assertEq(_kintoIDv1.lastMonitoredAt(), block.timestamp);
    }

    function testFailOnlyProviderCanMonitor() public {
        vm.startPrank(_user);
        _kintoIDv1.monitor(new address[](0), new IKintoID.MonitorUpdateData [][](0));
    }

    function testIsSanctionsMonitored() public {
        vm.startPrank(_kycProvider);
        _kintoIDv1.monitor(new address[](0), new IKintoID.MonitorUpdateData [][](0));
        assertEq(_kintoIDv1.isSanctionsMonitored(1), true);
        vm.warp(block.timestamp + 7 days);
        assertEq(_kintoIDv1.isSanctionsMonitored(8), true);
        assertEq(_kintoIDv1.isSanctionsMonitored(6), false);
    }

    function testSettingTraitsAndSanctions() public {
        vm.startPrank(_kycProvider);
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        address[] memory accounts = new address[](1);
        accounts[0] = _user;
        IKintoID.MonitorUpdateData[][] memory updates = new IKintoID.MonitorUpdateData[][](1);
        updates[0] = new IKintoID.MonitorUpdateData[](2);
        updates[0][0] = IKintoID.MonitorUpdateData(true, true, 5);
        updates[0][1] = IKintoID.MonitorUpdateData(true, false, 1); // remove 1
        _kintoIDv1.monitor(accounts, updates);
        assertEq(_kintoIDv1.hasTrait(_user,5), true);
        assertEq(_kintoIDv1.hasTrait(_user,1), false);
        assertEq(_kintoIDv1.isSanctionsSafeIn(_user,5), true);
        assertEq(_kintoIDv1.isSanctionsSafeIn(_user,1), true);
    }

    // Trait Tests
    function testProviderCanAddTrait() public {
        vm.startPrank(_kycProvider);
        _kintoIDv1.addTrait(_user, 1);
        assertEq(_kintoIDv1.hasTrait(_user,1), true);
    }

    function testFailUserCannotAddTrait() public {
        vm.startPrank(_user);
        _kintoIDv1.addTrait(_user, 1);
    }

    function testProviderCanRemoveTrait() public {
        vm.startPrank(_kycProvider);
        _kintoIDv1.addTrait(_user, 1);
        assertEq(_kintoIDv1.hasTrait(_user,1), true);
        _kintoIDv1.removeTrait(_user, 1);
        assertEq(_kintoIDv1.hasTrait(_user,1), false);
    }

    function testFailUserCannotRemoveTrait() public {
        vm.startPrank(_kycProvider);
        _kintoIDv1.addTrait(_user, 1);
        assertEq(_kintoIDv1.hasTrait(_user,1), true);
        vm.stopPrank();
        vm.startPrank(_user);
        _kintoIDv1.removeTrait(_user, 1);
    }

    // Sanction Tests
    function testProviderCanAddSanction() public {
        vm.startPrank(_kycProvider);
        _kintoIDv1.addSanction(_user, 1);
        assertEq(_kintoIDv1.isSanctionsSafeIn(_user,1), false);
        assertEq(_kintoIDv1.isSanctionsSafe(_user), false);
    }

    function testProviderCanRemoveSancion() public {
        vm.startPrank(_kycProvider);
        _kintoIDv1.addSanction(_user, 1);
        assertEq(_kintoIDv1.isSanctionsSafeIn(_user,1), false);
        _kintoIDv1.removeSanction(_user, 1);
        assertEq(_kintoIDv1.isSanctionsSafeIn(_user,1), true);
        assertEq(_kintoIDv1.isSanctionsSafe(_user), true);
    }

    function testFailUserCannotAddSanction() public {
        vm.startPrank(_user);
        _kintoIDv1.addSanction(_user2, 1);
    }

    function testFailUserCannotRemoveSanction() public {
        vm.startPrank(_kycProvider);
        _kintoIDv1.addSanction(_user, 1);
        assertEq(_kintoIDv1.isSanctionsSafeIn(_user,1), false);
        vm.stopPrank();
        vm.startPrank(_user);
        _kintoIDv1.removeSanction(_user2, 1);
    }

    // Transfer

    function testFailTransfersAreDisabled() public {
        IKintoID.SignatureData memory sigdata = _auxCreateSignature(_user, _user, 3, block.timestamp + 1000);
        uint8[] memory traits = new uint8[](1);
        traits[0] = 1;
        vm.startPrank(_kycProvider);
        assertEq(_kintoIDv1.isKYC(_user), false);
        _kintoIDv1.mintIndividualKyc(sigdata, traits);
        vm.stopPrank();
        vm.startPrank(_user);
        _kintoIDv1.safeTransferFrom(_user, _user2, _kintoIDv1.KYC_TOKEN_ID(), 1, '0x0');
        assertEq(_kintoIDv1.balanceOf(_user, _kintoIDv1.KYC_TOKEN_ID()), 0);
        assertEq(_kintoIDv1.balanceOf(_user2, _kintoIDv1.KYC_TOKEN_ID()), 1);

    }

    // Create a test for minting a KYC token
    function _auxCreateSignature(address _signer, address _account, uint256 _privateKey, uint256 _expiresAt) private view returns (
        IKintoID.SignatureData memory signData
    ) {
        bytes32 dataHash = keccak256(
            abi.encode(
                _signer,
                address(_kintoIDv1),
                _account,
                _kintoIDv1.KYC_TOKEN_ID(),
                _expiresAt,
                _kintoIDv1.nonces(_signer),
                bytes32(block.chainid)
            ));
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0x01),
                dataHash
            )
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        return IKintoID.SignatureData(
                _signer,
                _account,
                _kintoIDv1.nonces(_signer),
                _expiresAt,
                signature
            );
    }

    function auxDappSignature(IKintoID.SignatureData memory signData) public view returns (bool) {
        bytes32 dataHash = keccak256(abi.encode(
            signData.signer,
            0xa8bEb41Cf4721121ea58837eBDbd36169a7F246E,
            signData.account,
            _kintoIDv1.KYC_TOKEN_ID(),
            signData.expiresAt,
            _kintoIDv1.nonces(signData.signer),
            bytes32(block.chainid)
        ));
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0x01),
                dataHash
            )
        );
        hash = hash.toEthSignedMessageHash();
        // uint256 key = vm.envUint("FRONTEND_KEY");
        uint256 key = 1;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, hash);
        bytes memory newsignature = abi.encodePacked(r, s, v);
        bool valid = signData.signer.isValidSignatureNow(hash, newsignature);
        return valid;
    }

    function testDappSignature() public {
        // vm.startPrank(_kycProvider);
        // bytes memory sig = hex"0fcafa82e64fcfd3c38209e23270274132e88061f1718c7ff45e8c0ddbbe7cdd59b5af57e10a5d8221baa6ae37b57d02acace7e25fc29cb4025f15269e0939aa1b";
        // bool valid = auxDappSignature(
        //     IKintoID.SignatureData(
        //         0xf1cE2ca79D49B431652F9597947151cf21efB9C3,
        //         0xf1cE2ca79D49B431652F9597947151cf21efB9C3,
        //         0,
        //         1680614821,
        //         sig
        //     )
        // );
        // assertEq(valid, true);
    }
}

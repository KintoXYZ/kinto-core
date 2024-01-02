// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/Faucet.sol";
import "../src/interfaces/IFaucet.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract FaucetTest is Test {
    using ECDSA for bytes32;
    using SignatureChecker for address;

    Faucet _faucet;

    address _owner = address(1);
    address _user = vm.addr(3);

    // Create a aux function to create a signature for claiming kinto ETH from the faucet
    function _auxCreateSignature(address _signer, uint256 _privateKey, uint256 _expiresAt)
        private
        view
        returns (IFaucet.SignatureData memory signData)
    {
        bytes32 dataHash = keccak256(
            abi.encode(_signer, address(_faucet), _expiresAt, _faucet.nonces(_signer), bytes32(block.chainid))
        );
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), dataHash)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        return IFaucet.SignatureData(_signer, _faucet.nonces(_signer), _expiresAt, signature);
    }

    function setUp() public {
        vm.chainId(1);
        vm.startPrank(_owner);
        _faucet = new Faucet();
        vm.stopPrank();
    }

    function testUp() public {
        assertEq(_faucet.CLAIM_AMOUNT(), 1 ether / 200);
        assertEq(_faucet.FAUCET_AMOUNT(), 1 ether);
    }

    // Upgrade Tests

    function testOwnerCanStartFaucet() public {
        vm.startPrank(_owner);
        _faucet.startFaucet{value: 1 ether}();
        assertEq(address(_faucet).balance, _faucet.FAUCET_AMOUNT());

        vm.stopPrank();
    }

    function testFailOwnerCannotStartWithoutAmount() public {
        vm.startPrank(_owner);
        _faucet.startFaucet{value: 0.1 ether}();
        vm.stopPrank();
    }

    function testFailStartFaucetByOthers() public {
        vm.startPrank(_user);
        _faucet.startFaucet{value: 1 ether}();
        vm.stopPrank();
    }

    function testClaim() public {
        vm.startPrank(_owner);
        _faucet.startFaucet{value: 1 ether}();
        vm.stopPrank();
        vm.startPrank(_user);
        uint256 previousBalance = address(_user).balance;
        _faucet.claimKintoETH();
        assertEq(address(_faucet).balance, 1 ether - _faucet.CLAIM_AMOUNT());
        assertEq(address(_user).balance, previousBalance + _faucet.CLAIM_AMOUNT());
        vm.stopPrank();
    }

    function testFailIfClaimedTwice() public {
        vm.startPrank(_owner);
        _faucet.startFaucet{value: 1 ether}();
        vm.stopPrank();
        vm.startPrank(_user);
        _faucet.claimKintoETH();
        _faucet.claimKintoETH();
        vm.stopPrank();
    }

    function testClaimOnBehalf() public {
        IFaucet.SignatureData memory sigdata = _auxCreateSignature(_user, 3, block.timestamp + 1000);
        vm.startPrank(_owner);
        _faucet.startFaucet{value: 1 ether}();
        assertEq(_faucet.claimed(_user), false);
        assertEq(_faucet.nonces(_user), 0);
        _faucet.claimOnBehalf(sigdata);
        assertEq(_faucet.claimed(_user), true);
        assertEq(_faucet.nonces(_user), 1);
        vm.stopPrank();
    }
}

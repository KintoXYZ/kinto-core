// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "../src/interfaces/IFaucet.sol";
import "../src/Faucet.sol";
import "./helpers/UserOp.sol";
import "./helpers/UUPSProxy.sol";
import {AATestScaffolding} from "./helpers/AATestScaffolding.sol";

contract FaucetV999 is Faucet {
    function newFunction() external pure returns (uint256) {
        return 1;
    }

    constructor(address _kintoWalletFactory) Faucet(_kintoWalletFactory) {}
}

contract FaucetTest is UserOp, AATestScaffolding {
    using ECDSA for bytes32;

    UUPSProxy _proxyFaucet;
    Faucet _implFaucet;
    FaucetV999 _implFaucetV999;
    Faucet _faucet;
    FaucetV999 _FaucetV999;

    // Create a aux function to create an EIP-191 comploiant signature for claiming Kinto ETH from the faucet
    function _auxCreateSignature(address _signer, uint256 _privateKey, uint256 _expiresAt)
        private
        view
        returns (IFaucet.SignatureData memory signData)
    {
        bytes32 dataHash = keccak256(
            abi.encode(_signer, address(_faucet), _expiresAt, _faucet.nonces(_signer), bytes32(block.chainid))
        );
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash)); // EIP-191 compliant

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        return IFaucet.SignatureData(_signer, _faucet.nonces(_signer), _expiresAt, signature);
    }

    function setUp() public {
        vm.chainId(block.chainid);
        vm.startPrank(address(1));
        _owner.transfer(1e18);
        vm.stopPrank();
        deployAAScaffolding(_owner, 1, _kycProvider, _recoverer);
        vm.startPrank(_owner);
        _implFaucet = new Faucet{salt: 0}(address(_walletFactory));
        // deploy _proxy contract and point it to _implementation
        _proxyFaucet = new UUPSProxy{salt: 0}(address(_implFaucet), "");
        // wrap in ABI to support easier calls
        _faucet = Faucet(payable(address(_proxyFaucet)));
        // Initialize kyc viewer _proxy
        _faucet.initialize();
        vm.stopPrank();
    }

    function testUp() public {
        assertEq(_faucet.CLAIM_AMOUNT(), 1 ether / 2500);
        assertEq(_faucet.FAUCET_AMOUNT(), 1 ether);
    }

    /* ============ Upgrade Tests ============ */

    function testOwnerCanUpgradeViewer() public {
        vm.startPrank(_owner);
        FaucetV999 _implementationV2 = new FaucetV999(address(_walletFactory));
        _faucet.upgradeTo(address(_implementationV2));
        // re-wrap the _proxy
        _FaucetV999 = FaucetV999(payable(address(_faucet)));
        assertEq(_FaucetV999.newFunction(), 1);
        vm.stopPrank();
    }

    function test_RevertWhen_OthersCannotUpgradeFactory() public {
        FaucetV999 _implementationV2 = new FaucetV999(address(_walletFactory));
        vm.expectRevert("only owner");
        _faucet.upgradeTo(address(_implementationV2));
    }

    /* ============ Claim Tests ============ */

    function testOwnerCanStartFaucet() public {
        vm.startPrank(_owner);
        _faucet.startFaucet{value: 1 ether}();
        assertEq(address(_faucet).balance, _faucet.FAUCET_AMOUNT());

        vm.stopPrank();
    }

    function testStart_RevertWhen_OwnerCannotStartWithoutAmount(uint256 amt) public {
        vm.assume(amt < _faucet.FAUCET_AMOUNT());
        vm.prank(_owner);
        vm.expectRevert("Not enough ETH to start faucet");
        _faucet.startFaucet{value: amt}();
    }

    function testStart_RevertWhen_CallerIsNotOwner(address someone) public {
        vm.assume(someone != _faucet.owner());
        vm.deal(someone, 1 ether);
        vm.prank(someone);
        vm.expectRevert("Ownable: caller is not the owner");
        _faucet.startFaucet{value: 1 ether}();
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

    function testClaim_RevertWhen_ClaimedTwice() public {
        vm.prank(_owner);
        _faucet.startFaucet{value: 1 ether}();

        vm.startPrank(_user);
        _faucet.claimKintoETH();

        vm.expectRevert("You have already claimed your KintoETH");
        _faucet.claimKintoETH();
        vm.stopPrank();
    }

    function testClaimOnBehalf() public {
        IFaucet.SignatureData memory sigdata = _auxCreateSignature(_user, 3, block.timestamp + 1000);
        vm.startPrank(_owner);

        _faucet.startFaucet{value: 1 ether}();
        assertEq(_faucet.claimed(_user), false);
        assertEq(_faucet.nonces(_user), 0);

        _walletFactory.claimFromFaucet(address(_faucet), sigdata);
        assertEq(_faucet.claimed(_user), true);
        assertEq(_faucet.nonces(_user), 1);

        vm.stopPrank();
    }

    function testClaimOnBehalf_RevertWhen_CallerIsNotFactory() public {
        vm.prank(_owner);
        _faucet.startFaucet{value: 1 ether}();

        IFaucet.SignatureData memory sigdata = _auxCreateSignature(_user, 3, block.timestamp + 1000);
        vm.expectRevert("Only wallet factory can call this");
        _faucet.claimKintoETH(sigdata);
    }

    function testClaim_RevertWhen_FaucerIsNotActive() public {
        vm.prank(_owner);
        vm.expectRevert("Faucet is not active");
        _faucet.claimKintoETH();
    }

    // fixme: makes foundry to hang
    // function testClaim_DeactivatesWhenNotEnoughBalanceForNextClaim() public {
    //     vm.prank(_owner);
    //     _faucet.startFaucet{value: 1 ether}();

    //     for (uint256 i = 1; i <= 2500; i++) {
    //         vm.prank(vm.addr(i));
    //         _faucet.claimKintoETH();
    //     }
    //     // assert faucet is deactivated
    //     assertEq(address(_faucet).balance, 0);
    //     assertEq(_faucet.active(), false);
    // }

    /* ============ Withdraw Tests ============ */

    function testWithdrawAll() public {
        vm.startPrank(_owner);

        _faucet.startFaucet{value: 1 ether}();
        assertEq(address(_faucet).balance, 1 ether);

        _faucet.withdrawAll();
        assertEq(address(_faucet).balance, 0);

        vm.stopPrank();
    }

    function testWithdrawAll_RevertWhen_CallerIsNotOwner() public {
        vm.prank(_owner);
        _faucet.startFaucet{value: 1 ether}();
        assertEq(address(_faucet).balance, 1 ether);

        vm.expectRevert("Ownable: caller is not the owner");
        _faucet.withdrawAll();
    }
}

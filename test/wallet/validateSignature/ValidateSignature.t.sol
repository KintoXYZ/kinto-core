// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@aa/interfaces/IEntryPoint.sol";

import "../../../src/interfaces/IKintoWallet.sol";

import "../../../src/wallet/KintoWallet.sol";
import "../../../src/sample/Counter.sol";

import "../../harness/KintoWalletHarness.sol";
import {UserOp} from "../../helpers/UserOp.sol";
import {AATestScaffolding} from "../../helpers/AATestScaffolding.sol";

contract ValidateSignatureTest is AATestScaffolding, UserOp {
    uint256[] privateKeys;

    // constants
    uint256 constant SIG_VALIDATION_FAILED = 1;

    // events
    event UserOperationRevertReason(
        bytes32 indexed userOpHash, address indexed sender, uint256 nonce, bytes revertReason
    );
    event KintoWalletInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event WalletPolicyChanged(uint256 newPolicy, uint256 oldPolicy);
    event RecovererChanged(address indexed newRecoverer, address indexed recoverer);

    function setUp() public {
        deployAAScaffolding(_owner, 1, _kycProvider, _recoverer);

        // Add paymaster to _kintoWallet
        _fundSponsorForApp(address(_kintoWallet));

        // Default tests to use 1 private key for simplicity
        privateKeys = new uint256[](1);

        // Default tests to use _ownerPk unless otherwise specified
        privateKeys[0] = _ownerPk;
    }

    function testUp() public {
        assertEq(_kintoWallet.owners(0), _owner);
        assertEq(_entryPoint.walletFactory(), address(_walletFactory));
    }

    /* ============ _validateSignature ============ */

    function testValidateSignature_RevertWhen_OwnerIsNotKYCd() public {
        useHarness();
        revokeKYC(_kycProvider, _owner, _ownerPk);

        UserOperation memory userOp;
        assertEq(
            SIG_VALIDATION_FAILED,
            KintoWalletHarness(payable(address(_kintoWallet))).exposed_validateSignature(userOp, bytes32(0))
        );
    }

    function testValidateSignature_RevertWhen_SignatureLengthMismatch() public {
        useHarness();
        revokeKYC(_kycProvider, _owner, _ownerPk);

        UserOperation memory userOp;
        assertEq(
            SIG_VALIDATION_FAILED,
            KintoWalletHarness(payable(address(_kintoWallet))).exposed_validateSignature(userOp, bytes32(0))
        );
    }
}

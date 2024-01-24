// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@aa/interfaces/IEntryPoint.sol";

import "../src/interfaces/IKintoWallet.sol";

import "../src/wallet/KintoWallet.sol";
import "../src/sample/Counter.sol";

import "./harness/KintoWalletHarness.sol";
import "./harness/SponsorPaymasterHarness.sol";
import {UserOp} from "./helpers/UserOp.sol";
import {AATestScaffolding} from "./helpers/AATestScaffolding.sol";

contract SharedSetup is UserOp, AATestScaffolding {
    uint256[] privateKeys;
    Counter counter;

    // events
    event UserOperationRevertReason(
        bytes32 indexed userOpHash, address indexed sender, uint256 nonce, bytes revertReason
    );
    event KintoWalletInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event WalletPolicyChanged(uint256 newPolicy, uint256 oldPolicy);
    event RecovererChanged(address indexed newRecoverer, address indexed recoverer);
    event PostOpRevertReason(bytes32 indexed userOpHash, address indexed sender, uint256 nonce, bytes revertReason);

    function setUp() public virtual {
        deployAAScaffolding(_owner, 1, _kycProvider, _recoverer);

        // add paymaster to _kintoWallet
        fundSponsorForApp(address(_kintoWallet));

        // all tests will use 1 private key (_ownerPk) unless otherwise specified
        privateKeys = new uint256[](1);
        privateKeys[0] = _ownerPk;

        // deploy Counter contract
        counter = new Counter();
        assertEq(counter.count(), 0);

        registerApp(_owner, "test", address(counter));
        whitelistApp(address(counter));
        fundSponsorForApp(address(counter));
    }

    function testUp() public virtual {
        assertEq(_kintoWallet.owners(0), _owner);
        assertEq(_entryPoint.walletFactory(), address(_walletFactory));
        assertEq(_kintoWallet.getOwnersCount(), 1);
    }
}

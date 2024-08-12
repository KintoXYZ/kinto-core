// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@kinto-core-test/SharedSetup.t.sol";

contract ValidateSignatureTest is SharedSetup {
    // constants
    uint256 constant SIG_VALIDATION_FAILED = 1;
    uint256 constant SIG_VALIDATION_SUCCESS = 0;

    function setUp() public override {
        super.setUp();
        useHarness();
    }

    function testValidateSignature_RevertWhen_OwnerIsNotKYCd() public {
        revokeKYC(_kycProvider, _owner, _ownerPk);

        UserOperation memory userOp;
        assertEq(
            SIG_VALIDATION_FAILED,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    function testValidateSignature_RevertWhen_SignatureLengthMismatch() public {
        revokeKYC(_kycProvider, _owner, _ownerPk);

        UserOperation memory userOp;
        assertEq(
            SIG_VALIDATION_FAILED,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    function testValidateSignature_RevertWhen_UsingAppKey_SignatureLengthMismatch() public {
        revokeKYC(_kycProvider, _owner, _ownerPk);

        UserOperation memory userOp;
        assertEq(
            SIG_VALIDATION_FAILED,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    /* ============ with wallet policy (when execute) ============ */

    /* ============ single-signer ops (todo) ============ */

    function testValidateSignature_WhenOneSignerPolicy_WhenMultipleOwners_WhenOneSigner() public {
        // reset signers & change policy
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        resetSigners(owners, _kintoWallet.SINGLE_SIGNER());

        // create user op with only one signer
        privateKeys = new uint256[](1);
        privateKeys[0] = _ownerPk;

        // call increment
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    // @dev this use case would fail
    // function testValidateSignature_WhenOneSignerPolicy_WhenMultipleOwners_WhenOneSigner() public {}

    function testValidateSignature_WhenMultipleOwners_When1SignerPolicy() public {
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    /* ============ multi-signer ops ============ */

    function testValidateSignature_When2Owners_WhenAllSignersPolicy() public {
        // generate resetSigners UserOp to set 2 owners
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        resetSigners(owners, _kintoWallet.ALL_SIGNERS());

        // set private keys
        privateKeys = new uint256[](2);
        privateKeys[0] = _ownerPk;
        privateKeys[1] = _userPk;

        // create increment user op
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    function testValidateSignature_When3Owners_WhenAllSignersPolicy() public {
        address[] memory owners = new address[](3);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user2;

        resetSigners(owners, _kintoWallet.ALL_SIGNERS());

        // use only 2 signers
        privateKeys = new uint256[](2);
        privateKeys[0] = _ownerPk;
        privateKeys[1] = _userPk;

        // create op with wrong private keys
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce() + 1,
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_FAILED,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    function testValidateSignature_When2Owners_WhenAllSignersPolicy_WhenWrongSigners() public {
        //  change policy to 2 owners and all signers policy
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user;
        resetSigners(owners, _kintoWallet.ALL_SIGNERS());

        // create op with wrong private keys
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_FAILED,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    function testValidateSignature_When3Owners_WhenAllSignersPolicy_WhenWrongSigners() public {
        //  change policy to 3 owners and all signers policy
        address[] memory owners = new address[](3);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user2;
        resetSigners(owners, _kintoWallet.ALL_SIGNERS());

        // set private keys
        privateKeys = new uint256[](3);
        privateKeys[0] = _ownerPk;
        privateKeys[1] = _userPk;
        privateKeys[2] = _user2Pk;

        // create op with wrong private keys
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce() + 1,
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    /* ============ with wallet policy (when executeBatch) ============ */

    /* ============ single-signer ops ============ */

    function testValidateSignature_WhenExecuteBatch() public {
        address[] memory targets = new address[](3);
        targets[0] = address(_kintoWallet);
        targets[1] = address(counter);
        targets[2] = address(counter);

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSignature("recoverer()");
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    function testValidateSignature_WhenExecuteBatch_WhenChildren() public {
        // if intermediate calls are children of an app, it should validate the signature and sponsor will be the app

        // deploy new app
        Counter child = new Counter();

        // update app's metadata adding child
        address[] memory appContracts = new address[](1);
        appContracts[0] = address(child);

        updateMetadata(address(_kintoWallet), "test", address(counter), appContracts, new address[](0));

        address[] memory targets = new address[](3);
        targets[0] = address(_kintoWallet);
        targets[1] = address(child);
        targets[2] = address(counter);

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSignature("recoverer()");
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    function testValidateSignature_WhenExecuteBatch_WhenSponsoredContract() public {
        // if intermediate calls are sponsored contracts of an app, it should validate the signature and sponsor will be the app

        // deploy new app
        Counter sponsoredContract = new Counter();

        // add sponsored contract
        address[] memory contracts = new address[](1);
        contracts[0] = address(sponsoredContract);
        bool[] memory sponsored = new bool[](1);
        sponsored[0] = true;
        setSponsoredContracts(_owner, address(counter), contracts, sponsored);

        address[] memory targets = new address[](3);
        targets[0] = address(_kintoWallet);
        targets[1] = address(sponsoredContract);
        targets[2] = address(counter);

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSignature("recoverer()");
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    function testValidateSignature_WhenExecuteBatch_WhenChildrenAndSponsoredContract() public {
        // if intermediate calls are either sponsored contracts or children of an app, it should validate the signature and sponsor will be the app

        // deploy new app
        Counter sponsoredContract = new Counter();
        Counter child = new Counter();

        // add sponsored contract
        address[] memory contracts = new address[](1);
        contracts[0] = address(sponsoredContract);
        bool[] memory sponsored = new bool[](1);
        sponsored[0] = true;
        setSponsoredContracts(_owner, address(counter), contracts, sponsored);

        // update app's metadata passing a child
        address[] memory appContracts = new address[](1);
        appContracts[0] = address(child);
        updateMetadata(address(_kintoWallet), "test", address(counter), appContracts, new address[](0));

        address[] memory targets = new address[](4);
        targets[0] = address(_kintoWallet);
        targets[1] = address(child);
        targets[2] = address(sponsoredContract);
        targets[3] = address(counter);

        uint256[] memory values = new uint256[](4);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        values[3] = 0;

        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeWithSignature("recoverer()");
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");
        calls[3] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    function testValidateSignature_WhenExecuteBatch_WhenNotRelated() public {
        // if intermediate calls are neither sponsored contracts nor children of an app, it should NOT validate the signature

        // deploy new app
        Counter unknown = new Counter();

        address[] memory targets = new address[](3);
        targets[0] = address(_kintoWallet);
        targets[1] = address(unknown);
        targets[2] = address(counter);

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSignature("recoverer()");
        calls[1] = abi.encodeWithSignature("increment()");
        calls[2] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_FAILED,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    function testValidateSignature_WhenExecuteBatch_WhenMoreThanWalletCallsLimit() public {
        // if there are more than 3 calls to the wallet, it should NOT validate the signature
        uint256 limit = _kintoWallet.WALLET_TARGET_LIMIT();

        address[] memory targets = new address[](limit + 2);

        for (uint256 i = 0; i < limit + 1; i++) {
            targets[i] = address(_kintoWallet);
        }
        targets[limit + 1] = address(counter);

        uint256[] memory values = new uint256[](limit + 2);
        for (uint256 i = 0; i < limit + 2; i++) {
            values[i] = 0;
        }

        bytes[] memory calls = new bytes[](limit + 2);
        for (uint256 i = 0; i < limit + 2; i++) {
            calls[i] = abi.encodeWithSignature("recoverer()");
        }
        calls[limit + 1] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_FAILED,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    /* ============ multi-signer ops ============ */

    /* ============ using app key (when execute) ============ */

    function testValidateSignature_WhenAppKeyIsSet_WhenSignerIsAppKey() public {
        // it should skip the policy verification and use the app key
        // should validate the signature

        setAppKey(address(counter), _user);

        // create user op with app key as signer
        privateKeys[0] = _userPk;
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
        // todo: assert that it has used the app key and not the wallet policy
    }

    function testValidateSignature_WhenAppKeyIsSet_WhenSignerIsAppKey_WhenWalletHas2Signers() public {
        // it should skip the policy verification and use the app key
        // should validate the signature

        setAppKey(address(counter), _user);

        // reset signers & change policy
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user2;
        uint8 newPolicy = _kintoWallet.ALL_SIGNERS();
        resetSigners(owners, newPolicy);

        // create user op with the app key as signer
        privateKeys[0] = _userPk;
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
        // todo: assert that it has used the app key and not the wallet policy
    }

    function testValidateSignature_WhenAppKeyIsSet_WhenSignerIsAppKey_WhenCallToWallet() public {
        // since we are not allowing calls to the wallet, this would make the app key verification
        // to be skipped and will try to use the policy of the wallet
        // which will fail because the iSigner is not the owner
        // fixme: probably better to just make the signature fail when we realised that the signer is the app key and the call is to the wallet

        setAppKey(address(counter), _user);

        // create Counter increment transaction
        privateKeys[0] = _userPk; // we want to make use of the app key
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("isFunderWhitelisted()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_FAILED,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    function testValidateSignature_WhenAppKeyIsSet_WhenSignerIsOwner() public {
        // it should skip the app key verification and use the policy of the wallet
        // should validate the signature

        setAppKey(address(counter), _user);

        // create user op with the owner as signer
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
        // todo: we should be able to assert that it has used the policy of the wallet and not the app key
    }

    function testValidateSignature_WhenAppKeyIsSet_WhenSignerIsOwner_WhenCallToWallet() public {
        // it should skip the app key verification and use wallet policy
        // should validate the signature

        setAppKey(address(counter), _user);

        // try doing a wallet call and it should work
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(_kintoWallet),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("isFunderWhitelisted()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    /* ============ using app key (when executeBatch) ============ */

    function testValidateSignature_WhenAppKeyIsSet_WhenSignerIsAppKey_WhenExecuteBatch() public {
        setAppKey(address(counter), _user);

        address[] memory targets = new address[](2);
        targets[0] = address(counter);
        targets[1] = address(counter);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSignature("increment()");
        calls[1] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        privateKeys[0] = _userPk; // we want to make use of the app key
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    function testValidateSignature_WhenAppKeyIsSet_WhenSignerIsAppKey_WhenWalletHas2Signers_WhenExecuteBatch() public {
        // it should skip the policy verification and use the app key
        // should validate the signature

        // reset signers & change policy
        address[] memory owners = new address[](2);
        owners[0] = _owner;
        owners[1] = _user2;

        resetSigners(owners, _kintoWallet.ALL_SIGNERS());

        setAppKey(address(counter), _user);

        address[] memory targets = new address[](2);
        targets[0] = address(counter);
        targets[1] = address(counter);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSignature("increment()");
        calls[1] = abi.encodeWithSignature("increment()");

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        privateKeys[0] = _userPk; // we want to make use of the app key
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    function testValidateSignature_WhenAppKeyIsSet_WhenSignerIsAppKey_WhenCallToWallet_WhenExecuteBatch(uint256 order)
        public
    {
        // it should skip the app key verification and use wallet policy
        // should validate the signature

        uint256 CALLS_NUMBER = 5;
        vm.assume(order < CALLS_NUMBER);
        // it should skip the wallet policy and use the app key verification
        // should NOT validate the signature since it's forbidden to call the wallet

        setAppKey(address(counter), _user);

        // prep batch: 5 calls in a batch which will include a call to the wallet (in different orders)
        address[] memory targets = new address[](CALLS_NUMBER);
        uint256[] memory values = new uint256[](CALLS_NUMBER);
        bytes[] memory calls = new bytes[](CALLS_NUMBER);

        for (uint256 i = 0; i < CALLS_NUMBER; i++) {
            values[i] = 0;
            if (i == order) {
                targets[i] = address(_kintoWallet);
                calls[i] = abi.encodeWithSignature("recoverer()");
            } else {
                targets[i] = address(counter);
                calls[i] = abi.encodeWithSignature("increment()");
            }
        }
        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        privateKeys[0] = _userPk; // we want to make use of the app key
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_FAILED,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
        // todo: assert that it has used the app key and not the wallet policy
    }

    function testValidateSignature_WhenAppKeyIsSet_WhenSignerIsOwner_WhenExecuteBatch() public {}

    function testValidateSignature_WhenAppKeyIsSet_WhenSignerIsOwner_WhenCallToWallet_WhenExecuteBatch(uint256 order)
        public
    {
        // it should skip the app key verification and use wallet policy
        // should validate the signature

        uint256 CALLS_NUMBER = 5;
        vm.assume(order < CALLS_NUMBER);
        // it should skip the wallet policy and use the app key verification
        // should NOT validate the signature since it's forbidden to call the wallet

        setAppKey(address(counter), _user);

        // prep batch: 5 calls in a batch which will include a call to the wallet (in different orders)
        address[] memory targets = new address[](CALLS_NUMBER);
        uint256[] memory values = new uint256[](CALLS_NUMBER);
        bytes[] memory calls = new bytes[](CALLS_NUMBER);

        for (uint256 i = 0; i < CALLS_NUMBER - 1; i++) {
            values[i] = 0;
            if (i == order) {
                targets[i] = address(_kintoWallet);
                calls[i] = abi.encodeWithSignature("recoverer()");
            } else {
                targets[i] = address(counter);
                calls[i] = abi.encodeWithSignature("increment()");
            }
        }

        // last call must be to the app
        targets[CALLS_NUMBER - 1] = address(counter);
        calls[CALLS_NUMBER - 1] = abi.encodeWithSignature("increment()");
        values[CALLS_NUMBER - 1] = 0;

        OperationParamsBatch memory opParams = OperationParamsBatch({targets: targets, values: values, bytesOps: calls});
        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet), _kintoWallet.getNonce(), privateKeys, opParams, address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
        // todo: assert that it has used the app key and not the wallet policy
    }

    /* ============ special cases ============ */

    function testValidateSignature_WhenTwoSigner_When4Owners() public {
        // reset signers & change policy
        address[] memory owners = new address[](4);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user2;
        owners[3] = _user3;
        resetSigners(owners, _kintoWallet.TWO_SIGNERS());

        // create user op with owners 1 and 2 as signers
        privateKeys = new uint256[](2);
        privateKeys[0] = _ownerPk;
        privateKeys[1] = _userPk;

        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );

        // create user op with owners 3 and 4 as signers
        privateKeys[0] = _user2Pk;
        privateKeys[1] = _user3Pk;

        userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    // requiredSigners == 2, owners.length == 3 and the owners 1 and 2 provided their signatures.
    function testValidateSignature_MinusOneSigner() public {
        // reset signers & change policy
        address[] memory owners = new address[](3);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user2;
        resetSigners(owners, _kintoWallet.MINUS_ONE_SIGNER());

        // create user op with owners 1 and 2 as signers
        privateKeys = new uint256[](2);
        privateKeys[0] = _userPk;
        privateKeys[1] = _user2Pk;

        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );

        // create user op with owners 1 and 2 as signers but in reverse order
        privateKeys[0] = _user2Pk;
        privateKeys[1] = _userPk;

        userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    // special case 2: requiredSigners == 1, owners.length == 3 and the owner 2 is the signer.
    // validation should fail since SINGLE_SIGNER policy only works with the first owner, any extra
    // owners are ignored
    function testValidateSignature_WhenSingleSigner_When3Owners() public {
        // reset signers & change policy
        address[] memory owners = new address[](3);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user2;
        resetSigners(owners, _kintoWallet.SINGLE_SIGNER());

        // create user op with owners 1 as signer
        privateKeys = new uint256[](1);
        privateKeys[0] = _userPk;

        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_FAILED,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    // special case 2: requiredSigners == 3, owners.length == 3 and only owners[0] is KYCd
    // should validate the signature since we don't care about the other owners being KYC'd
    function testValidateSignature_WhenAllSigners3Owners() public {
        assertEq(_kintoID.isKYC(_user), false);
        assertEq(_kintoID.isKYC(_user2), false);

        // reset signers & change policy
        address[] memory owners = new address[](3);
        owners[0] = _owner;
        owners[1] = _user;
        owners[2] = _user2;
        resetSigners(owners, _kintoWallet.ALL_SIGNERS());

        // create user op with owners 1 as signer
        privateKeys = new uint256[](3);
        privateKeys[0] = _ownerPk;
        privateKeys[1] = _userPk;
        privateKeys[2] = _user2Pk;

        UserOperation memory userOp = _createUserOperation(
            address(_kintoWallet),
            address(counter),
            _kintoWallet.getNonce(),
            privateKeys,
            abi.encodeWithSignature("increment()"),
            address(_paymaster)
        );

        assertEq(
            SIG_VALIDATION_SUCCESS,
            KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
                userOp, _entryPoint.getUserOpHash(userOp)
            )
        );
    }

    // If a KintoWallet has more than one owner and the first owner burns their KYC, the rest lose access to the wallet
    // because _validateSignature() reverts if the first owner does not have KYC:
    // function testValidateSignature_SpecialCase4() public {
    //     address[] memory owners = new address[](2);
    //     owners[0] = _owner;
    //     owners[1] = _user;
    //     resetSigners(owners, _kintoWallet.SINGLE_SIGNER());

    //     revokeKYC(_kycProvider, _owner, _ownerPk);

    //     // create user op with owners[1] as signer
    //     privateKeys = new uint256[](1);
    //     privateKeys[0] = _userPk;

    //     UserOperation memory userOp = _createUserOperation(
    //         address(_kintoWallet),
    //         address(counter),
    //         _kintoWallet.getNonce(),
    //         privateKeys,
    //         abi.encodeWithSignature("increment()"),
    //         address(_paymaster)
    //     );

    //     assertEq(
    //         SIG_VALIDATION_SUCCESS,
    //         KintoWalletHarness(payable(address(_kintoWallet))).validateSignature(
    //             userOp, _entryPoint.getUserOpHash(userOp)
    //         )
    //     );
    // }
}

import "setup.spec";
import "../Initializable.spec";

/// @title The allowed signer policies are either SINGLE_SIGNER(), MINUS_ONE_SIGNER() or ALL_SIGNERS().
invariant AllowedSignerPolicy()
    signerPolicy() == SINGLE_SIGNER() ||
    signerPolicy() == MINUS_ONE_SIGNER() ||
    signerPolicy() == TWO_SIGNERS() ||
    signerPolicy() == ALL_SIGNERS();

/// @title The appSigner() of the zero address is the zero address.
invariant ZeroAddressApp()
    appSigner(0) == 0;

/// @title The number of the wallet owners is three at most.
invariant NumberOfOwnersIntegrity()
    assert_uint256(MAX_SIGNERS()) >= getOwnersCount()
    {
        preserved initialize(address owner, address recoverer) with (env e) {
            /// Factory initializes right after deployment.
            require getOwnersCount() == 0;
        }
    }

/// @title The zero address is never an owner.
invariant OwnerisNonZero()
    getOwnersCount() > 0 => !isOwner(0)
    {
        preserved initialize(address owner, address recoverer) with (env eP) {
            /// Guaranteed in KintoWalletFactory.createAccount():
            /// require(kintoID.isKYC(owner), 'KYC required');
            /// and by the invariant in KintoID: ZeroAddressNotKYC()
            require owner !=0;
        }
    }

/// @title The owners array has no duplicates (no two identical owners).
invariant OwnerListNoDuplicates()
    ( getOwnersCount() == 2 => (owners(0) != owners(1) && owners(1) !=0) ) &&
    ( getOwnersCount() == 3 => (owners(0) != owners(1) && owners(0) != owners(2) && owners(1) != owners(2)) )
    {
        preserved {
            requireInvariant NumberOfOwnersIntegrity();
        }
    }

/// @title The signer policy can never exceed the required owners account.
invariant SignerPolicyCannotExceedOwnerCount()
    (initialized != MAX_VERSION()) => (
        (signerPolicy() == SINGLE_SIGNER() => getOwnersCount() >= 1) &&
        (signerPolicy() == MINUS_ONE_SIGNER() => getOwnersCount() > 1) &&
        (signerPolicy() == TWO_SIGNERS() => getOwnersCount() > 1) &&
        (signerPolicy() == ALL_SIGNERS() => getOwnersCount() >= 1)
    )
    {
        preserved {
            requireInvariant AllowedSignerPolicy();
            requireInvariant NumberOfOwnersIntegrity();
        }
        preserved execute(address A, uint256 B, bytes C) with (env e) {
            require initialized != MAX_VERSION();
        }
        preserved executeBatch(address[] A, uint256[] B, bytes[] C) with (env e) {
            require initialized != MAX_VERSION();
        }
    }

/// @title The first wallet owner (owners(0)) is always KYC.
/// @notice We assume that after completeRecovery() the new owner was minted KYC. 
invariant FirstOwnerIsKYC(env e)
    (e.block.timestamp > 0 && getOwnersCount() > 0) => isKYC_CVL(e.block.timestamp, owners(0))
    /// We assume that when finishing recovery the new owner has already been minted KYC by the providers.
    /// Also, see rule 'firstOwnerIsChangedOnlyByRecovery'.
    filtered{f -> f.selector != sig:completeRecovery(address[]).selector}
    {
        preserved with (env eP) {
            require eP.block.timestamp == e.block.timestamp;
        }
        preserved initialize(address owner, address recoverer) with (env eP) {
            require eP.block.timestamp == e.block.timestamp;
            /// Guaranteed in KintoWalletFactory.createAccount():
            /// require(kintoID.isKYC(owner), 'KYC required');
            require(isKYC_CVL(eP.block.timestamp, owner));
        }
    } 

/// @title Only the resetSigners() and completeRecovery() functions can remove an owner().
rule whichFunctionRemovesOwner(address account, method f) filtered{f -> !f.isView} {
    requireInvariant NumberOfOwnersIntegrity();

    bool ownerBefore = isOwner(account);
        env e;
        calldataarg args;
        /// Assuming initializing right after proxy deployment.
        if(f.selector == sig:initialize(address,address).selector) {
            require getOwnersCount() == 0;
        }
        f(e, args);
    bool ownerAfter = isOwner(account);

    assert ownerBefore && !ownerAfter => isResetSigners(f);
}

/// @title The first owner can only be changed by the completeRecovery() function (post-initialization).
rule firstOwnerIsChangedOnlyByRecovery(method f) filtered{f -> !f.isView} {
    address firstOwner_before = owners(0);
        env e;
        calldataarg args;
        f(e, args);
    address firstOwner_after = owners(0);  

    assert firstOwner_after != firstOwner_before => f.selector == sig:completeRecovery(address[]).selector;
}

/// @title completeRecovery() sets the three owners to the three new signers.
rule completeRecoveryIntegrity() {
    env e;
    address[] signers;
    completeRecovery(e, signers);
    assert owners(0) == signers[0];
    assert owners(1) == signers[1];
    assert owners(2) == signers[2];
}

/// @title If the validation succeeds, the signer's identity must correct (owner or app signer).
rule validationSignerIntegrity() {
    env e;
    requireInvariant NumberOfOwnersIntegrity();
    requireInvariant OwnerisNonZero();
    requireInvariant ZeroAddressApp();
    requireInvariant SignerPolicyCannotExceedOwnerCount();
    require initialized != MAX_VERSION();

    KintoWallet.UserOperation userOp;
    bytes32 userOpHash;
    uint256 missingAccountFunds;
    uint256 validationData = validateUserOp(e, userOp, userOpHash, missingAccountFunds);
    /// Assuming the validation succeeded:
    require validationData == 0;
    /// Sponsor app from userOp:
    address app = appRegistry.getApp(ghostAppContract);
    /// userOp hash + Eth signature hash:
    bytes32 hash = signedMessageHash(userOpHash);
    /// Hash message signer:
    address signer = recoverCVL(hash, userOp.signature);

    bool appHasSigner = appSigner(app) != 0;

    assert !appHasSigner => isOwner(signer), "Owner must be signer of wallet transaction";
    assert (appHasSigner && !isOwner(signer)) => appSigner(app) == signer, "App signer must sign for app transaction";
}

/// @title If the validation succeeds, then all relevant signers (according to policy) must be owners.
rule validationSignerPolicyIntegrity(uint8 policy, uint256 ownersCount) {
    /// Require invariants:
    requireInvariant NumberOfOwnersIntegrity();
    requireInvariant OwnerisNonZero();
    requireInvariant SignerPolicyCannotExceedOwnerCount();
    requireInvariant OwnerListNoDuplicates();
    requireInvariant AllowedSignerPolicy();
    requireInvariant ZeroAddressApp();
    /// Set rule parameters:
    require ownersCount == getOwnersCount();
    require policy == signerPolicy();
    
    env e;
    KintoWallet.UserOperation userOp;
    bytes32 userOpHash;
    uint256 missingAccountFunds;
    uint256 validationData = validateUserOp(e, userOp, userOpHash, missingAccountFunds);
    /// Assume success:
    require validationData == 0;
    /// Assume signers (non-app) validation:
    require appRegistry.getApp(ghostAppContract) == 0;

    /// Get hash message signers:
    uint256 signaturesLength = userOp.signature.length;
    bytes32 hash = signedMessageHash(userOpHash);
    /// Check if signers are wallet owners:
    bool isOwner_0 = isOwner(recoverCVL(hash, extractSigCVL(userOp.signature, 0)));
    bool isOwner_1 = isOwner(recoverCVL(hash, extractSigCVL(userOp.signature, 1)));
    bool isOwner_2 = isOwner(recoverCVL(hash, extractSigCVL(userOp.signature, 2)));
    bool isOwner_3 = isOwner(recoverCVL(hash, extractSigCVL(userOp.signature, 3)));

    if(policy == SINGLE_SIGNER()) {
        assert userOp.signature.length == 65;
        assert isOwner_0 || isOwner_1 || isOwner_2 || isOwner_3;
    }
    else if(policy == MINUS_ONE_SIGNER()) {
        assert signaturesLength == assert_uint256(65 * (ownersCount - 1));
        if(ownersCount == 1) {
            assert false;
        }
        else if(ownersCount == 2) {
            assert isOwner_0 || isOwner_1;
        }
        else if(ownersCount == 3) {
            assert (isOwner_0 && isOwner_1) || (isOwner_1 && isOwner_2)  || (isOwner_0 && isOwner_2);
        }
        else if(ownersCount == 4) {
            assert (isOwner_0 && isOwner_1 && isOwner_2) || 
                   (isOwner_0 && isOwner_1 && isOwner_3) || 
                   (isOwner_0 && isOwner_2 && isOwner_3) || 
                   (isOwner_1 && isOwner_2 && isOwner_3);
        }
    }
    else if(policy == ALL_SIGNERS()) {
        assert signaturesLength == assert_uint256(65 * ownersCount);
        if(ownersCount == 1) {
            assert isOwner_0;
        }
        else if(ownersCount == 2) {
            assert isOwner_0 && isOwner_1;
        }
        else if(ownersCount == 3) {
            assert isOwner_0 && isOwner_1 && isOwner_2;
        }
        else {
            assert isOwner_0 && isOwner_1 && isOwner_2 && isOwner_3;
        }
    }
    else if(policy == TWO_SIGNERS()) {
        assert signaturesLength == assert_uint256(65 * 2);
        if(ownersCount == 1) {
            assert false;
        }
        assert (isOwner_0 && isOwner_1) || (isOwner_0 && isOwner_2)  || (isOwner_0 && isOwner_3) || (isOwner_1 && isOwner_2) || (isOwner_1 && isOwner_3) || (isOwner_2 && isOwner_3);
    }
    assert true;
}
/// @title If there are signers duplicates in the validation process, it must return "failed".
rule signatureDuplicatesCannotBeVerified() {
    /// Require invariants:
    requireInvariant NumberOfOwnersIntegrity();
    requireInvariant OwnerisNonZero();
    requireInvariant SignerPolicyCannotExceedOwnerCount();
    requireInvariant OwnerListNoDuplicates();
    requireInvariant AllowedSignerPolicy();
    requireInvariant ZeroAddressApp();
    /// Set rule parameters:
    uint256 ownersCount = getOwnersCount();
    uint8 policy = signerPolicy();
    
    env e;
    KintoWallet.UserOperation userOp;
    require to_mathint(userOp.signature.length) <= 65 * 4;
    bytes32 userOpHash; bytes32 hash = signedMessageHash(userOpHash);
    uint256 missingAccountFunds;
    uint256 validationData = validateUserOp(e, userOp, userOpHash, missingAccountFunds);
    require appRegistry.getApp(ghostAppContract) == 0;

    address signer0 = recoverCVL(hash, extractSigCVL(userOp.signature, 0));
    address signer1 = recoverCVL(hash, extractSigCVL(userOp.signature, 1));
    address signer2 = recoverCVL(hash, extractSigCVL(userOp.signature, 2));

    if(ownersCount == 2 && policy == ALL_SIGNERS()) {
        assert signer0 == signer1 => validationData == 1;
    }
    else if(ownersCount == 3 && policy == ALL_SIGNERS()) {
        assert (signer0 == signer1 || signer0 == signer2 || signer2 == signer1) => validationData == 1;
    }
    else if(ownersCount == 3 && policy == MINUS_ONE_SIGNER()) {
        assert signer0 == signer1 => validationData == 1;
    }
    assert true;
}

/// @title execute(), executeBatch() and validateUserOp() are only called by the EntryPoint.
rule entryPointPriviligedFunctions(method f) 
filtered{f -> entryPointPriviliged(f)} {
    env e;
    calldataarg args;
    f(e, args);
    assert e.msg.sender == entryPoint();
}

/// @title Only the contract can change the app white list and by calling setAppWhitelist() or whitelistAppAndSetKey().
rule whichFunctionsChangeWhiteList(address app, method f) filtered{f -> !f.isView} {
    env e;
    calldataarg args;
    bool isWhiteList_before = appWhitelist(app);
        f(e, args);
    bool isWhiteList_after = appWhitelist(app);
    
    assert isWhiteList_after != isWhiteList_before =>
        (f.selector == sig:whitelistApp(address[],bool[]).selector || f.selector == sig:whitelistAppAndSetKey(address,address).selector) && senderIsSelf(e);
}

/// @title Only the contract can change the funder white list and by calling setFunderWhitelist().
rule whichFunctionsChangeFunderWhiteList(address app, method f) filtered{f -> !f.isView} {
    env e;
    calldataarg args;
    bool isWhiteList_before = funderWhitelist(app);
        f(e, args);
    bool isWhiteList_after = funderWhitelist(app);

    assert isWhiteList_after != isWhiteList_before => 
        f.selector == sig:setFunderWhitelist(address[],bool[]).selector && senderIsSelf(e);
}

/// @title Only the contract can change the funder whitelist and by calling setAppKey(), whitelistApp(), or whitelistAppAndSetKey().
rule whichFunctionsChangeAppSigner(address app, method f) filtered{f -> !f.isView} {
    env e;
    calldataarg args;
    address signer_before = appSigner(app);
        f(e, args);
    address signer_after = appSigner(app);
    
    assert signer_before != signer_after => 
        (f.selector == sig:setAppKey(address,address).selector || f.selector == sig:whitelistApp(address[],bool[]).selector || f.selector == sig:whitelistAppAndSetKey(address,address).selector) && senderIsSelf(e);

}

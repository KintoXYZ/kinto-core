import "setup.spec";
import "IERC721.spec";

use invariant AdminRoleIsDefaultRole filtered{f -> !upgradeMethods(f) && !monitorMethods(f)}
use invariant lastMonitoredAtInThePast filtered{f -> !upgradeMethods(f)}
use invariant TokenIndexIsUpToArrayLength filtered{f -> !upgradeMethods(f)}
use invariant NoOwnerNoIndex filtered{f -> !upgradeMethods(f)}
use invariant TokenAtIndexConsistency filtered{f -> !upgradeMethods(f)}
use invariant TokenBalanceIsZeroOrOne filtered{f -> !upgradeMethods(f)}
use invariant IsOwnedInTokensArray filtered{f -> !upgradeMethods(f)}
use invariant RecoveryTargetsIsZero filtered{f -> !upgradeMethods(f)}
use rule onlyRoleAdminRevokesRole filtered{f -> !upgradeMethods(f) && !monitorMethods(f)}

methods {
    function isSanctioned(address, uint16) external returns (bool);
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rules: ERC721                                                                                                    │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
/// @title The owner of a token could only be transferred to, or from the zero address.
rule ownerCanChangeOnlyFromZeroAndBack(uint256 tokenID, method f) filtered{f -> !viewOrUpgrade(f) && !recoveryMethod(f)} {
    requireInvariant RecoveryTargetsIsZero();

    address ownerBefore = ownerOf(tokenID);
        env e;
        calldataarg args;
        f(e, args);
    address ownerAfter = ownerOf(tokenID);

    assert ownerAfter != ownerBefore => (ownerBefore == 0 || ownerAfter == 0);
}

/// @title Only the admin or the factory can call the recovery method 
rule onlyAdminOrFactoryRecovers(method f) filtered{f -> recoveryMethod(f)} {
    env e;
    calldataarg args;
    bool callerIsAdmin = hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender);
    bool callerIsFactory = e.msg.sender == walletFactory();
    f(e, args);

    assert callerIsAdmin || callerIsFactory;
}

/// @title Correctness of ownership change through recover methods.
rule ownerChangeThroughRecovery(method f, uint256 tokenID) filtered{f -> recoveryMethod(f)} {
    address ownerBefore = ownerOf(tokenID);
    address from;
    address to;
    env e;
    if(f.selector == sig:transferOnRecovery(address,address).selector) {
        transferOnRecovery(e, from, to);
    }
    else {
        assert false, "Didn't expect other recovery methods";
    }
    address ownerAfter = ownerOf(tokenID);

    assert ownerAfter != ownerBefore => (ownerBefore == from && ownerAfter == to);
}

/// @title Recovery methods cannot add new tokens in KintoID.
rule recoveryMethodDoesntChangeTokens(method f) filtered{f -> recoveryMethod(f)} {
    requireInvariant RecoveryTargetsIsZero();
    uint256 nextToken_before = nextTokenId();
    uint256 NumberOfTokens_before = NumberOfTokens;
        env e;
        calldataarg args;
        f(e, args);
    uint256 nextToken_after = nextTokenId();
    uint256 NumberOfTokens_after = NumberOfTokens;

    assert nextToken_before == nextToken_after && NumberOfTokens_before == NumberOfTokens_after;
}

/// @title Only the _nextTokenID+1 is minted, and only by the mintCompanyKyc() or mintIndividualKyc() functions.
rule mintOnlyNextID(address account, method f) filtered{f -> !viewOrUpgrade(f) && !recoveryMethod(f)} {
    uint256 tokenID = require_uint256(nextTokenId() + 1);
    requireInvariant RecoveryTargetsIsZero();
    requireInvariant TokenBalanceIsZeroOrOne(account);

    uint256 balanceBefore = balanceOf(account);
    address ownerBefore = ownerOf(tokenID);
        env e;
        calldataarg args;
        f(e, args);
    uint256 balanceAfter = balanceOf(account);
    address ownerAfter = ownerOf(tokenID);

    assert balanceAfter > balanceBefore => ownerBefore != ownerAfter;
    assert balanceAfter > balanceBefore => (
        f.selector == sig:mintCompanyKyc(IKintoID.SignatureData,uint16[]).selector || 
        f.selector == sig:mintIndividualKyc(IKintoID.SignatureData,uint16[]).selector
    );
}

/// @title The new owner of the nextTokenID is the only one who is being minted a token.
rule mintToOwnerOnly(bool companyOrIndividual) {
    env e;
    uint16[] traits;
    IKintoID.SignatureData signatureData;

    address account = signatureData.signer;
    uint256 tokenID = require_uint256(nextTokenId() + 1);
    address ownerBefore = ownerOf(tokenID);
    if(companyOrIndividual) {
        mintCompanyKyc(e, signatureData, traits);
    }
    else {
        mintIndividualKyc(e, signatureData, traits);
    }
    address ownerAfter = ownerOf(tokenID);

    assert ownerBefore != ownerAfter;
    assert ownerAfter == account;
}

/// @title only a KYC provider can change anyone's ERC721 balance.
rule onlyKYCCanChangeBalance(address account, method f) filtered{f -> !viewOrUpgrade(f)} {
    requireInvariant RecoveryTargetsIsZero();

    uint256 balanceBefore = balanceOf(account);
        env e;
        calldataarg args;
            f(e,args);
    uint256 balanceAfter = balanceOf(account);

    assert balanceBefore != balanceAfter => 
       (hasRole(KYC_PROVIDER_ROLE(), e.msg.sender) || recoveryMethod(f));
}

/// @title It's impossible for the owner of any token to burn his own token.
rule burnByOwnerIsImpossible(uint256 tokenID) {
    address owner = ownerOf(tokenID);

    require balanceOf(owner) != 0; /// Can only burn if already minted (thus has balance).
    require totalSupply() != 0; /// Assuming totalSupply() == sum of balances.
    uint256 tokenIDEnd;
    require tokensIndex[tokenIDEnd] == assert_uint256(NumberOfTokens - 1);
    requireInvariant TokenIndexIsUpToArrayLength(tokenID);
    requireInvariant TokenIndexIsUpToArrayLength(tokenIDEnd);
    env e; 
        require e.msg.sender == owner; /// Owner of token is the msg.sender.
        require e.msg.value == 0; /// Not a payable function.
    burn@withrevert(e, tokenID);
    
    assert lastReverted;
}

/// @title It's impossible, by anyone, to burn a KYC token right after it's being minted.
rule cannotBurnRightAfterMint(IKintoID.SignatureData signatureData) {
    bool companyOrIndividual;
    env e1;
    env e2;
    uint16[] traits;
    if(companyOrIndividual) {
        mintCompanyKyc(e1, signatureData, traits);
    }
    else {
        mintIndividualKyc(e1, signatureData, traits);
    }
    burnKYC@withrevert(e2, signatureData);

    assert lastReverted;
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rules: sanctions                                                                                                    │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/

/// @title If an account is sanctioned anywhere, then its sanctions count is non-zero.
invariant hasSanctionCountIsNonZero(env e1, address account, uint16 CID)
    isSanctioned(e1, account, CID) => getSanctionsCount(account) > 0
    filtered{f -> !upgradeMethods(f)}
    {
        preserved with (env e2) {
            require e2.block.timestamp == e1.block.timestamp;
        }
        preserved monitor(address[] accounts, IKintoID.MonitorUpdateData[][] data) with (env e2) {
            require e2.block.timestamp == e1.block.timestamp;
            if(accounts.length > 0) {
                require accounts.length == 1;
                require data[0].length == 1;
                uint16 CID_A = data[0][0].index;
                address accountA = accounts[0];
                require (accountA == account && CID_A != CID &&
                isSanctioned(e2, accountA, CID_A) && isSanctioned(e2, accountA, CID)) => getSanctionsCount(accountA) > 1;
            }
        }
        preserved removeSanction(address accountA, uint16 CID_A) with (env e2) {
            require e2.block.timestamp == e1.block.timestamp;
            require (accountA == account  && CID_A != CID &&
                isSanctioned(e2, accountA, CID_A) && isSanctioned(e2, accountA, CID)) => getSanctionsCount(accountA) > 1;
        }
    }

/// @title only the addSanction(), removeSanction(), and monitor() functions can change the sanction status (ignoring last minotred time).
rule onlySanctionMethodCanSanction(method f) filtered{f -> !viewOrUpgrade(f)} {
    address account; uint16 CID;
    env e;

    bool sanctioned_before = isSanctioned(e, account, CID);
        calldataarg args;
        f(e, args);
    bool sanctioned_after = isSanctioned(e, account, CID);

    assert !sanctioned_before && sanctioned_after =>
        (f.selector == sig:addSanction(address,uint16).selector || monitorMethods(f));
    assert sanctioned_before && !sanctioned_after =>
        (f.selector == sig:removeSanction(address,uint16).selector || monitorMethods(f));
}

/// @title The addSanction() function:
/// (a) Must turn on the sanction status for the correct countryID and account.
/// (b) Must increase the sanction count for that account by 1.
rule addSanctionIntegrity(address account, uint16 CID) {
    address account_B;
    uint16 CID_B;
    env e1;
    bool sanctioned_before = isSanctioned(e1, account_B, CID_B);
    uint8 count_before = getSanctionsCount(account_B);
        addSanction(e1, account, CID);
    bool sanctioned_after = isSanctioned(e1, account_B, CID_B);
    uint8 count_after = getSanctionsCount(account_B);
    
    assert (account == account_B && CID == CID_B) =>
        sanctioned_after, "adding a sanction must turn on the sanction";
    assert !(account == account_B && CID == CID_B) =>
        (sanctioned_after == sanctioned_before), "addSanction must change the correct account and country";
    assert (sanctioned_before != sanctioned_after) => count_after - count_before == 1,
        "The number of sanctions must increase by 1";
}

/// @title The removeSanction() function:
/// (a) Must turn off the sanction status for the correct countryID and account.
/// (b) Must decrease the sanction count for that account by 1.
rule removeSanctionIntegrity(address account, uint16 CID) {
    address account_B;
    uint16 CID_B;
    env e1;
    bool sanctioned_before = isSanctioned(e1, account_B, CID_B);
    uint8 count_before = getSanctionsCount(account_B);
        removeSanction(e1, account, CID);
    bool sanctioned_after = isSanctioned(e1, account_B, CID_B);
    uint8 count_after = getSanctionsCount(account_B);
    
    assert (account == account_B && CID == CID_B) =>
        !sanctioned_after, "removing a sanction must turn off the sanction";
    assert !(account == account_B && CID == CID_B) =>
        (sanctioned_after == sanctioned_before), "addSanction must change the correct account and country";
    assert (sanctioned_before != sanctioned_after) => count_before - count_after == 1,
        "The number of sanctions must decrease by 1";
}

/// @title The addSanction() function has no effect if the account is already sanctioned in the same country.
rule addSanctionIdempotent(address account, uint16 CID) {
    env e1;
    bool sanctioned_before = isSanctioned(e1, account, CID);
    storage stateBefore = lastStorage;
        addSanction(e1, account, CID);
    storage stateAfter = lastStorage;

    assert sanctioned_before => stateBefore[currentContract] == stateAfter[currentContract],
        "Adding a sanction a second time shouldn't change anything";
}

/// @title The removeSanction() function has no effect if the account is not sanctioned in the same country.
rule removeSanctionIdempotent(address account, uint16 CID) {
    env e1;
    bool sanctioned_before = isSanctioned(e1, account, CID);
    storage stateBefore = lastStorage;
        require e1.block.timestamp == lastMonitoredAt();
        removeSanction(e1, account, CID);
    storage stateAfter = lastStorage;

    assert !sanctioned_before => stateBefore[currentContract] == stateAfter[currentContract],
        "Removing a sanction a second time shouldn't change anything";
}

/// @title addSanction() is commutative with respect to the account and country ID.
rule addSanctionCommutativity() {
    env e;
    address accountA; uint16 CID_A;
    address accountB; uint16 CID_B;
    
    storage initState = lastStorage;
        addSanction(e, accountA, CID_A) at initState;
        addSanction(e, accountB, CID_B);
    storage stateA = lastStorage;
        addSanction(e, accountB, CID_B) at initState;
        addSanction(e, accountA, CID_A);
    storage stateB = lastStorage;

    assert stateA[currentContract] == stateB[currentContract];
}

/// @title removeSanction() is commutative with respect to the account and country ID.
rule removeSanctionCommutativity() {
    env e;
    address accountA; uint16 CID_A;
    address accountB; uint16 CID_B;
    
    storage initState = lastStorage;
        removeSanction(e, accountA, CID_A) at initState;
        removeSanction(e, accountB, CID_B);
    storage stateA = lastStorage;
        removeSanction(e, accountB, CID_B) at initState;
        removeSanction(e, accountA, CID_A);
    storage stateB = lastStorage;

    assert stateA[currentContract] == stateB[currentContract];
}

/// @title Any sanction that was added could later be removed (by any KYC provider).
rule addedSanctionCanBeRemoved(address account, uint16 CID) {
    env e1;
    env e2; require e2.msg.value == 0; 
    requireInvariant hasSanctionCountIsNonZero(e1, account, CID);
    requireInvariant hasSanctionCountIsNonZero(e2, account, CID);

    bool hasRole1 = hasRole(KYC_PROVIDER_ROLE(), e1.msg.sender);
    bool hasRole2 = hasRole(KYC_PROVIDER_ROLE(), e2.msg.sender);
    addSanction(e1, account, CID);
    assert hasRole1;

    removeSanction@withrevert(e2, account, CID);
    assert hasRole2 => !lastReverted;
}

/// @title Any sanction that was removed could later be added (by any KYC provider).
rule removedSanctionCanBeAdded(address account, uint16 CID) {
    env e1;
    env e2; require e2.msg.value == 0;
    requireInvariant hasSanctionCountIsNonZero(e1, account, CID);
    requireInvariant hasSanctionCountIsNonZero(e2, account, CID);

    bool hasRole1 = hasRole(KYC_PROVIDER_ROLE(), e1.msg.sender);
    bool hasRole2 = hasRole(KYC_PROVIDER_ROLE(), e2.msg.sender);
    removeSanction(e1, account, CID);
    assert hasRole1;

    addSanction@withrevert(e2, account, CID);
    assert hasRole2 => !lastReverted;
}

/// @title addSanction() or removeSanction() are account and countryID independent.
rule addingOrRemovingSanctionsAreIndependent(bool addOrRemove_A, bool addOrRemove_B) {
    env eA;
    env eB;
    address accountA; uint16 CID_A;
    address accountB; uint16 CID_B;
    requireInvariant hasSanctionCountIsNonZero(eA, accountA, CID_A);
    requireInvariant hasSanctionCountIsNonZero(eB, accountB, CID_B);
    require (accountA == accountB && CID_A != CID_B) => (
        (isSanctioned(eA, accountA, CID_A) && isSanctioned(eB, accountB, CID_B)) => getSanctionsCount(accountA) >= 2);

    storage initState = lastStorage;
    if(addOrRemove_A) {
        addSanction(eA, accountA, CID_A) at initState;
    }
    else {
        removeSanction(eA, accountA, CID_A) at initState;
    }

    if(addOrRemove_B) {
        addSanction(eB, accountB, CID_B) at initState;
    }
    else {
        removeSanction(eB, accountB, CID_B) at initState;
    }
    if(addOrRemove_A) {
        addSanction@withrevert(eA, accountA, CID_A);
    }
    else {
        removeSanction@withrevert(eA, accountA, CID_A);
    }

    assert !lastReverted;
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rules: Traits                                                                                                    │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/

/// @title Any trait that was added could later be removed (by any KYC provider).
rule addedTraitCanBeRemoved(address account, uint8 TID) {
    env e1;
    env e2; require e2.msg.value == 0;

    bool hasRole1 = hasRole(KYC_PROVIDER_ROLE(), e1.msg.sender);
    bool hasRole2 = hasRole(KYC_PROVIDER_ROLE(), e2.msg.sender);
    addTrait(e1, account, TID);
    assert hasRole1;

    removeTrait@withrevert(e2, account, TID);
    assert hasRole2 => !lastReverted;
}

/// @title Any trait that was removed could later be added (by any KYC provider).
rule removedTraitCanBeAdded(address account, uint8 TID) {
    env e1;
    env e2; require e2.msg.value == 0;

    bool hasRole1 = hasRole(KYC_PROVIDER_ROLE(), e1.msg.sender);
    bool hasRole2 = hasRole(KYC_PROVIDER_ROLE(), e2.msg.sender);
    removeTrait(e1, account, TID);
    assert hasRole1;

    addTrait@withrevert(e2, account, TID);
    assert hasRole2 => !lastReverted;
}

/// @title Integrity of nonce transition:
/// (a) Nonces cannot decrease and can increase by 1 at most.
/// (b) A nonce could only change for one signer at a time.
rule noncesIncreaseCorrectly(method f) filtered{f -> !viewOrUpgrade(f)} {
    address signerA;
    address signerB;

    uint256 nonceA_before = nonces(signerA);
    uint256 nonceB_before = nonces(signerB);
        env e;
        calldataarg args;
        f(e, args);
    uint256 nonceA_after = nonces(signerA);
    uint256 nonceB_after = nonces(signerB);

    assert nonceA_before == nonceA_after || 
        nonceA_after - nonceA_before == 1, "nonces cannot decrease and can increase by 1 at most";
    assert (nonceA_before != nonceA_after) && (nonceB_before != nonceB_after) =>
        signerA == signerB, "A nonce could only change for one signer at a time";
}

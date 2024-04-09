import "setup.spec";

use invariant lastMonitoredAtInThePast filtered{f -> !upgradeMethods(f)}

/// @title Auxiliary rule: checks which functions change the isKYC status.
/*rule whichFunctionsChange_isKYC(address account, method f) filtered{f -> !viewOrUpgrade(f)} {
    env e1;
    env e2; calldataarg args;
    
    bool isBefore = isKYC(e1, account);
        f(e2, args);
    bool isAfter = isKYC(e1, account);
    assert isBefore == isAfter;
}*/

/// @title isKYC() cannot revert.
rule isKYC_cannotRevert(method f) filtered{f -> !viewOrUpgrade(f)} {
    env e1;
    env e2; calldataarg args;
    require e1.block.timestamp >= e2.block.timestamp;
    address account;
    requireInvariant lastMonitoredAtInThePast(e1);

    storage initState = lastStorage;
    isKYC(e1, account) at initState;

    f(e2, args) at initState;
    isKYC@withrevert(e1, account);

    assert !lastReverted;
}

/// @title isSanctionsSafeIn() cannot revert.
rule isSanctionsSafeIn_cannotRevert(method f) filtered{f -> !viewOrUpgrade(f)} {
    env e1;
    env e2; calldataarg args;
    require e1.block.timestamp >= e2.block.timestamp;
    address account; uint16 countryId;
    requireInvariant lastMonitoredAtInThePast(e1);

    storage initState = lastStorage;
    isSanctionsSafeIn(e1, account, countryId) at initState;

    f(e2, args) at initState;
    isSanctionsSafeIn@withrevert(e1, account, countryId);

    assert !lastReverted;
}

/// @title isSanctionsSafe() cannot revert.
rule isSanctionsSafe_cannotRevert(method f) filtered{f -> !viewOrUpgrade(f)} {
    env e1;
    env e2; calldataarg args;
    require e1.block.timestamp >= e2.block.timestamp;
    address account;
    requireInvariant lastMonitoredAtInThePast(e1);

    storage initState = lastStorage;
    isSanctionsSafe(e1, account) at initState;

    f(e2, args) at initState;
    isSanctionsSafe@withrevert(e1, account);

    assert !lastReverted;
}

/// @title isCompany() cannot revert.
rule isCompany_cannotRevert(method f) filtered{f -> !viewOrUpgrade(f)} {
    env e1;
    env e2; calldataarg args;
    require e1.block.timestamp >= e2.block.timestamp;
    address account;
    requireInvariant lastMonitoredAtInThePast(e1);

    storage initState = lastStorage;
    isCompany(e1, account) at initState;

    f(e2, args) at initState;
    isCompany@withrevert(e1, account);

    assert !lastReverted;
}

/// @title isIndividual cannot revert.
rule isIndividual_cannotRevert(method f) filtered{f -> !viewOrUpgrade(f)} {
    env e1;
    env e2; calldataarg args;
    require e1.block.timestamp >= e2.block.timestamp;
    address account;
    requireInvariant lastMonitoredAtInThePast(e1);

    storage initState = lastStorage;
    isIndividual(e1, account) at initState;

    f(e2, args) at initState;
    isIndividual@withrevert(e1, account);

    assert !lastReverted;
}

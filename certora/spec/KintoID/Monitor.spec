import "setup.spec";
use invariant lastMonitoredAtInThePast filtered{f -> !upgradeMethods(f)}
use invariant RecoveryTargetsIsZero filtered{f -> !upgradeMethods(f)}

/// @title Monitor doesn't change roles
rule monitorDoesntChangeRoles(bytes32 role, address account) {
    env e;
    calldataarg args;
    bool hasRole_before = hasRole(role, account);
    bytes32 role_admin_before = getRoleAdmin(role);
        monitor(e, args);
    bool hasRole_after = hasRole(role, account);
    bytes32 role_admin_after = getRoleAdmin(role);

    assert hasRole_before == hasRole_after;
    assert role_admin_before == role_admin_after;
}

/// @title An account which is not a KYC provider cannot make monitor() revert. 
rule monitorCannotRevertByNonProvider(method f) filtered{f -> !viewOrUpgrade(f)} {
    env e1;
    env e2; calldataarg args;
    requireInvariant RecoveryTargetsIsZero();
    /// For simplicity, consider a single account and one data.
    address account; address[] accounts = [account];
    IKintoID.MonitorUpdateData data; IKintoID.MonitorUpdateData[][] traits = [[data]];
    
    storage initState = lastStorage;
    bool senderIsProvider = hasRole(KYC_PROVIDER_ROLE(), e2.msg.sender);
    bool senderIsRoleAdmin = hasRole(getRoleAdmin(KYC_PROVIDER_ROLE()), e2.msg.sender) || hasRole(DEFAULT_ADMIN_ROLE(), e2.msg.sender);
    bool senderIsFactory = e2.msg.sender == walletFactory();

    monitor(e1, accounts, traits) at initState;

    f(e2, args) at initState;
    monitor@withrevert(e1, accounts, traits);

    assert !senderIsProvider && !senderIsRoleAdmin && !senderIsFactory => !lastReverted;
    assert lastReverted && recoveryMethod(f) => (senderIsFactory || senderIsRoleAdmin);
}

/// @title The monitor() function is commutative with respect to update data, if the IDs are different (for a single account).  
rule monitorSanctionsCommutative(address account) {
    address[] accounts = [account];
    IKintoID.MonitorUpdateData data1;
    IKintoID.MonitorUpdateData data2;

    IKintoID.MonitorUpdateData[][] traits1 = [[data1,data2]];
    IKintoID.MonitorUpdateData[][] traits2 = [[data2,data1]];

    env e;
    storage initState = lastStorage;
        monitor(e, accounts, traits1) at initState;
    storage state1 = lastStorage;
        monitor(e, accounts, traits2) at initState;
    storage state2 = lastStorage;

    assert (data1.index & 0xff != data2.index & 0xff) => state1[currentContract] == state2[currentContract];
}

/// @title The monitor() function is associative with respect to the updated data (for a single account).
rule monitorSanctionsAssociative(address account) {
    address[] accounts = [account];
    IKintoID.MonitorUpdateData data1;
    IKintoID.MonitorUpdateData data2;

    IKintoID.MonitorUpdateData[][] traits1 = [[data1]];
    IKintoID.MonitorUpdateData[][] traits2 = [[data2]];
    IKintoID.MonitorUpdateData[][] traits12 = [[data1,data2]];

    env e;
    storage initState = lastStorage;
        monitor(e, accounts, traits1) at initState;
        monitor(e, accounts, traits2);
    storage state1 = lastStorage;
        monitor(e, accounts, traits12) at initState;
    storage state2 = lastStorage;

    assert state1[currentContract] == state2[currentContract];
}

/// @title The monitor() function is associative with respect to the accounts list (for any data).
rule monitorAccountsAssociative(address account1, address account2) {
    address[] accounts1 = [account1];
    address[] accounts2 = [account2];
    address[] accounts12 = [account1, account2];
    IKintoID.MonitorUpdateData data1;
    IKintoID.MonitorUpdateData data2;

    IKintoID.MonitorUpdateData[][] traits1 = [[data1]];
    IKintoID.MonitorUpdateData[][] traits2 = [[data2]];
    IKintoID.MonitorUpdateData[][] traits12 = [[data1],[data2]];

    env e;
    storage initState = lastStorage;
        monitor(e, accounts1, traits1) at initState;
        monitor(e, accounts2, traits2);
    storage state1 = lastStorage;
        monitor(e, accounts12, traits12) at initState;
    storage state2 = lastStorage;

    assert state1[currentContract] == state2[currentContract];
}

/// @title The monitor() function is commutative with respect to the accounts list (for a single type of data).
rule monitorAccountsCommutative(address account1, address account2) {
    address[] accounts1 = [account1, account2];
    address[] accounts2 = [account2, account1];
    IKintoID.MonitorUpdateData data;

    IKintoID.MonitorUpdateData[][] traits = [[data],[data]];

    env e;
    storage initState = lastStorage;
        monitor(e, accounts1, traits) at initState;
    storage state1 = lastStorage;
        monitor(e, accounts2, traits) at initState;
    storage state2 = lastStorage;

    assert state1[currentContract] == state2[currentContract];
}

/// @title The monitor() function cannot front-run and cause a subsequent call to monitor() revert, for a single account.
rule monitorSanctionsCannotFrontRun(address account) {
    address[] accounts = [account];
    env e1;
    env e2;
    require e1.block.timestamp >= e2.block.timestamp;
    require e2.block.timestamp > 0;
    requireInvariant lastMonitoredAtInThePast(e1);
    requireInvariant lastMonitoredAtInThePast(e2);
    
    IKintoID.MonitorUpdateData data1;
    IKintoID.MonitorUpdateData data2;
    IKintoID.MonitorUpdateData[][] traits1 = [[data1]];
    IKintoID.MonitorUpdateData[][] traits2 = [[data2]];

    uint16 CID1 = data1.index;
    uint16 CID2 = data2.index;
    require (CID1 != CID2) => (
        (isSanctioned(e1, account, CID1) && isSanctioned(e2, account, CID2)) => getSanctionsCount(account) >= 2
    );

    storage initState = lastStorage;
    monitor(e1, accounts, traits1) at initState;

    monitor(e2, accounts, traits2) at initState;
    monitor@withrevert(e1, accounts, traits1);

    assert !lastReverted;
}

/// @title The monitor() function cannot front-run and cause a subsequent call to monitor() revert (for indepndent accounts).
rule monitorAccountsCannotFrontRun(address account1, address account2) {
    address[] accounts1 = [account1];
    address[] accounts2 = [account2];
    
    IKintoID.MonitorUpdateData data1;
    IKintoID.MonitorUpdateData data2;
    IKintoID.MonitorUpdateData[][] traits1 = [[data1]];
    IKintoID.MonitorUpdateData[][] traits2 = [[data2]];

    env e1;
    env e2;
    require e1.block.timestamp >= e2.block.timestamp;
    require account1 != account2;

    storage initState = lastStorage;
    monitor(e1, accounts1, traits1) at initState;

    monitor(e2, accounts2, traits2) at initState;
    monitor@withrevert(e1, accounts1, traits1);

    assert !lastReverted;
}

/// @title A KYC provider can always call monitor() with empty data.
rule monitorEmptyDataSucceeds() {
    env e;
    require e.msg.value == 0; /// Non-payable function
    require hasRole(KYC_PROVIDER_ROLE(), e.msg.sender); /// Sender is KYC provider
    address[] accounts;
    IKintoID.MonitorUpdateData[][] traits;

    monitor@withrevert(e, accounts, traits);
    assert (traits.length == 0 && accounts.length == 0) => !lastReverted;
}
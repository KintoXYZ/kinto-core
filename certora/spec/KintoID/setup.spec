using KintoIDHarness as kintoID;
using KYCViewer as viewer;

methods {
    /// IERC1822ProxiableUpgradeable
    function _.proxiableUUID() external => ERC1822ProxiableUUID(calledContract) expect bytes32;

    /// KintoID
    function kintoID.lastMonitoredAt() external returns (uint256) envfree;
    function kintoID.isSanctionsSafeIn(address,uint16) external returns (bool);
    function kintoID.nonces(address) external returns (uint256) envfree;
    function kintoID.KYC_PROVIDER_ROLE() external returns (bytes32) envfree;
    function kintoID.DEFAULT_ADMIN_ROLE() external returns (bytes32) envfree;
    function kintoID.hasRole(bytes32, address) external returns (bool) envfree;
    function kintoID.getRoleAdmin(bytes32) external returns (bytes32) envfree;
    function kintoID.nextTokenId() external returns (uint256) envfree;
    function kintoID.walletFactory() external returns (address) envfree;

    /// KYCViewer
    function viewer.isKYC(address addr) external returns (bool);
    function viewer.isSanctionsSafe(address account) external returns (bool);
    function viewer.isSanctionsSafeIn(address account, uint16 _countryId) external returns (bool);
    function viewer.isCompany(address account) external returns (bool) envfree;
    function viewer.isIndividual(address account) external returns (bool) envfree;

    // IERC721Receiver
    function _.onERC721Received(address,address,uint256,bytes) external => NONDET;

    // IFaucet
    function _.claimOnCreation(address) external => NONDET;
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Ghost & hooks: sanctions meta data                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
/// Maximum number of sanctions (assumed).
definition MAX_SANCTIONS() returns uint8 = 200;

ghost mapping(address => uint8) _sanctionsCount {
    init_state axiom forall address account. _sanctionsCount[account] == 0;
    axiom forall address account. _sanctionsCount[account] <= MAX_SANCTIONS();
}

hook Sload uint8 count _kycmetas[KEY address account].sanctionsCount {
    require _sanctionsCount[account] == count;
}

hook Sstore _kycmetas[KEY address account].sanctionsCount uint8 count (uint8 count_old) {
    require _sanctionsCount[account] == count_old;
    _sanctionsCount[account] = count;
}

ghost mapping(address => address) _recoveryTargets {
    init_state axiom forall address account. _recoveryTargets[account] ==0;
}

hook Sload address target recoveryTargets[KEY address account] {
    require _recoveryTargets[account] == target;
}

hook Sstore recoveryTargets[KEY address account] address target (address target_old) {
    _recoveryTargets[account] = target;
}

function getSanctionsCount(address account) returns uint8 {
    return _sanctionsCount[account];
}

ghost ERC1822ProxiableUUID(address) returns bytes32;

definition transferMethods(method f) returns bool = 
    f.selector == sig:transferFrom(address,address,uint256).selector ||
    f.selector == sig:safeTransferFrom(address,address,uint256).selector ||
    f.selector == sig:safeTransferFrom(address,address,uint256,bytes).selector;

definition upgradeMethods(method f) returns bool = 
    f.selector == sig:upgradeToAndCall(address,bytes).selector;

definition monitorMethods(method f) returns bool = 
    f.selector == sig:monitor(address[],IKintoID.MonitorUpdateData[][]).selector;

definition viewOrUpgrade(method f) returns bool = upgradeMethods(f) || f.isView;

definition recoveryMethod(method f) returns bool = 
    f.selector == sig:transferOnRecovery(address,address).selector;

definition senderIsSelf(env e) returns bool = e.msg.sender == currentContract;

/// @title the recovery target address is always zero (before and after function call)
invariant RecoveryTargetsIsZero()
    forall address account. _recoveryTargets[account] == 0
    {
        preserved with (env e) {
            require e.msg.sender != 0;
        }
    }

/// @title lastMonitoredAt() is never in the future.
invariant lastMonitoredAtInThePast(env e)
    e.block.timestamp >= lastMonitoredAt()
    {
        preserved with (env eP) {
            require e.block.timestamp == eP.block.timestamp;
        }
    }

/// @title The role admin of any role is the DEFAULT_ADMIN_ROLE()
invariant AdminRoleIsDefaultRole(bytes32 role)
    getRoleAdmin(role) == DEFAULT_ADMIN_ROLE()
    {
        preserved with (env e) {require e.msg.sender != 0;}
    }

/// @title Only the DEFAULT_ADMIN_ROLE() can revoke/grant a role from/to an account.
rule onlyRoleAdminRevokesRole(method f, bytes32 role, address account) {
    requireInvariant AdminRoleIsDefaultRole(role);

    bool hasRole_before = hasRole(role, account);
        env e;
        calldataarg args;
        f(e,args);
    bool hasRole_after = hasRole(role, account);

    assert (hasRole_before != hasRole_after && account != e.msg.sender) =>
        hasRole(DEFAULT_ADMIN_ROLE(), e.msg.sender);
}

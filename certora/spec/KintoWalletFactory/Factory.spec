using KintoWalletFactory as factory;

methods {
    /// Factory
    function factory.getWalletTimestamp(address wallet) external returns (uint256) envfree;
    //function factory._preventCreationBytecode(bytes calldata) internal => NONDET;

    /// IKintoID
    function _.isKYC(address account) external with (env e) => isKYC_CVL(e.block.timestamp, account) expect bool;
    /// IEntryPoint
    function _.walletFactory() external => Factory() expect address;
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Setup                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/

definition Factory() returns address = factory;

definition isWalletActive(address wallet) returns bool = factory.getWalletTimestamp(wallet) > 0;

/// Mock for the KintoID.isKYC(uint256 timestamp, address account) function.
function isKYC_CVL(uint256 time, address account) returns bool {
    return _isKYC[time][account];
}

persistent ghost mapping(uint256 => mapping(address => bool)) _isKYC {
    /// Based on the invariant in KintoID: ZeroAddressNotKYC()
    axiom forall uint256 time. !_isKYC[time][0];
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rules                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
/*
/// @title The address of the contract created by createAccount() must match the value of getAddress() with the same parameters.
rule createAccountCorrectAddress() {
    env e;
    require e.block.timestamp > 0;
    address owner; address recoverer; bytes32 salt1; bytes32 salt2;
    address walletCreated = createAccount(e, owner, recoverer, salt1);
    address walletAddress = getAddress(e, owner, recoverer, salt2);

    assert salt1 == salt2 <=> walletCreated == walletAddress;
}

/// @title getAddress() function is injective with respect to the owner, recoverer and salt values.
rule getAddressInjectivity() {
    env e;
    require e.block.timestamp > 0;
    address owner1; address owner2; 
    address recoverer1; address recoverer2;
    bytes32 salt1; bytes32 salt2;
    address walletAddress1 = getAddress(e, owner1, recoverer1, salt1);
    address walletAddress2 = getAddress(e, owner2, recoverer2, salt2);

    assert owner1 != owner2 => walletAddress1 != walletAddress2;
    assert recoverer1 != recoverer2 => walletAddress1 != walletAddress2;
    assert salt1 != salt2 => walletAddress1 != walletAddress2;
}
*/

/// @title Once a wallet is active (timestamp > 0), it never becomes inactive (timestamp = 0).
rule onceActiveAlwaysActive(address wallet, method f) 
filtered{f -> !f.isView && f.selector != sig:upgradeToAndCall(address,bytes).selector} {
    bool isActive_before = isWalletActive(wallet);
        env e;
        require e.block.timestamp > 0;
        calldataarg args;
        f(e, args);
    bool isActive_after = isWalletActive(wallet);

    assert isActive_before => isActive_after;
}

/// @title A wallet could only become active (created) for an owner who is KYCd.
rule createWalletForKYCdOnly(address wallet) {
    bool isActive_before = isWalletActive(wallet);
        env e;
        require e.block.timestamp > 0;
        address owner; address recoverer; bytes32 salt;
        createAccount(e, owner, recoverer, salt);
    bool isActive_after = isWalletActive(wallet);

    assert (!isActive_before && isActive_after) => isKYC_CVL(e.block.timestamp, owner);
}

/// @title The zero address is never a wallet owner or a wallet recoverer.
rule ZeroAddressIsNeitherWalletOwnerNorRecoverer() {
    env e;
    address owner; 
    address recoverer; bytes32 salt;
    createAccount(e, owner, recoverer, salt);

    assert owner !=0;
    assert recoverer !=0;
}
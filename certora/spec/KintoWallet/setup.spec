using MockECDSA as MockECDSA;
using BytesLibMock as BytesLibMock;
using KintoAppRegistry as appRegistry;

methods {
    /// KintoWallet
    function entryPoint() external returns (address) envfree;
    function getNonce() external returns (uint) envfree;
    function getOwnersCount() external returns (uint) envfree;
    function owners(uint256) external returns (address) envfree;
    function recoverer() external returns (address) envfree;
    function inRecovery() external returns (uint256) envfree;
    function funderWhitelist(address) external returns (bool) envfree;
    function appSigner(address) external returns (address) envfree;
    function appWhitelist(address) external returns (bool) envfree;
    function getOwnersCount() external returns (uint) envfree;
    function signerPolicy() external returns (uint8) envfree;
    function SINGLE_SIGNER() external returns (uint8) envfree;
    function MINUS_ONE_SIGNER() external returns (uint8) envfree;
    function ALL_SIGNERS() external returns (uint8) envfree;
    function MAX_SIGNERS() external returns (uint8) envfree;
    function TWO_SIGNERS() external returns (uint8) envfree;
    function KintoWallet._decodeCallData(bytes calldata) internal returns (address,bool) => randomAppContract();

    /// BytesSignature
    function BytesLibMock.extractSignature(bytes32, uint256) external returns (bytes memory) envfree;
    function ByteSignature.extractECDASignatureFromBytes(bytes memory fullSignature, uint position)
        internal returns (bytes memory) => extractSigCVL(fullSignature, position);

    /// ECDSA
    function MockECDSA.recoverMock(bytes32, bytes) external returns (address) envfree;
    function ECDSA.recover(bytes32 hash, bytes memory signature) internal returns (address) => recoverCVL(hash, signature);
    function ECDSA.toEthSignedMessageHash(bytes32 hash) internal returns (bytes32) => signedMessageHash(hash);

    /// IKintoID
    function _.isKYC(address account) external with (env e) => isKYC_CVL(e.block.timestamp, account) expect bool;

    /// appRegistry
    function appRegistry.getApp(address) external returns (address) envfree;
    function appRegistry.tokenURI(uint256) external returns (string) => NONDET DELETE;
}

definition senderIsSelf(env e) returns bool = e.msg.sender == currentContract;

definition entryPointPriviliged(method f) returns bool = 
    f.selector == sig:execute(address,uint256,bytes).selector ||
    f.selector == sig:executeBatch(address[],uint256[],bytes[]).selector ||
    f.selector == sig:validateUserOp(KintoWallet.UserOperation,bytes32,uint256).selector;

definition isResetSigners(method f) returns bool = 
    f.selector == sig:completeRecovery(address[]).selector ||
    f.selector == sig:resetSigners(address[],uint8).selector;

/// Mock for the KintoID.isKYC(uint256 timestamp, address account) function.
function isKYC_CVL(uint256 time, address account) returns bool {
    return _isKYC[time][account];
}

/// Generic ghost function for function toEthSignedMessageHash(bytes32 hash)
persistent ghost signedMessageHash(bytes32) returns bytes32;

function recoverCVL(bytes32 hash, bytes signature) returns address {
    return MockECDSA.recoverMock(hash, signature);
}

function extractSigCVL(bytes fullSignature, uint position) returns bytes {
    /// Only one signature - no need to extract.
    if(fullSignature.length == 65) return fullSignature;
    /// Multiple signatures - use extract mock.
    bytes32 signatureHash = keccak256(fullSignature);
    return BytesLibMock.extractSignature(signatureHash, position);
}

function isOwner(address account) returns bool {
    uint256 count = getOwnersCount();
    if(count == 1) {return account == owners(0);}
    else if(count == 2) {return account == owners(0) || account == owners(1);}
    else if(count == 3) {return account == owners(0) || account == owners(1) || account == owners(2);}
    else if(count == 4) {return account == owners(0) || account == owners(1) || account == owners(2) || account == owners(3);}
    return false;
}

persistent ghost mapping(uint256 => mapping(address => bool)) _isKYC {
    /// Based on the invariant in KintoID: ZeroAddressNotKYC()
    axiom forall uint256 time. !_isKYC[time][0];
}

/// A random (NONDET) summary for _decodeCallData(bytes callData) that stores the output in a ghost variable.
/// The ghost address could be later fetched outside the call to validateUserOp().
ghost address ghostAppContract;

function randomAppContract() returns (address,bool) {
    address _arbAppContract;
    bool batched; 
    ghostAppContract = _arbAppContract;
    return (ghostAppContract, batched);
}

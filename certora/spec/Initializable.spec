definition MAX_VERSION() returns uint8 = max_uint8;

persistent ghost uint8 initialized {init_state axiom initialized == 0;}
persistent ghost bool initializing {init_state axiom initializing == false;}

hook Sload uint8 value _initialized {
    require initialized == value;
}

hook Sstore _initialized uint8 value {
    initialized = value;
}

hook Sload bool value _initializing {
    require initializing == value;
}

hook Sstore _initializing bool value {
    initializing = value;
}

function initializingDisabled() returns bool {
    return initialized == MAX_VERSION();
}

rule cannotInitializeIfDisabled() {
    requireInvariant initializingIsDisabled();

    env e; calldataarg args;
    initialize@withrevert(e, args);
    assert lastReverted;
}

invariant initializingIsDisabled()
    initializingDisabled()
    filtered{f -> f.selector != sig:initialize(address,address).selector}

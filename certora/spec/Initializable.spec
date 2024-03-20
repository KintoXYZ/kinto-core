definition MAX_VERSION() returns uint8 = max_uint8;

ghost uint8 initialized {init_state axiom initialized == 0;}
ghost bool initializing {init_state axiom initializing == false;}

hook Sload uint8 value _initialized STORAGE {
    require initialized == value;
}

hook Sstore _initialized uint8 value STORAGE {
    initialized = value;
}

hook Sload bool value _initializing STORAGE {
    require initializing == value;
}

hook Sstore _initializing bool value STORAGE {
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
    filtered{f -> f.selector != initialize(address,address,address).selector}

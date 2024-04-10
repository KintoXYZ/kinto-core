rule viewFunctionsDontRevert(method f, method g) 
filtered{f -> f.isView, g -> !g.isView} {
    env e1; calldataarg args1;
    env e2; calldataarg args2;

    storage initState = lastStorage;
    f(e1, args1) at initState;

    g(e2, args2) at initState;
    f@withrevert(e1, args1);

    assert !lastReverted;
}

rule sanity(method f) {
    env e;
    calldataarg args;
    f(e, args);
    satisfy true;
}

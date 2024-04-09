import "SponsorPaymaster.spec";

/// @title A call validatePaymasterUserOp() from a different wallet owner can never front-run another call to the same function and make it revert.
/// @notice The EntryPoint calls both validatePaymasterUserOp() and postOp() in the same flow. So we must batch these two calls
/// together to one operation, which we would like to verify that cannot be front-run.
rule validatePayMasterCannotFrontRunEachOther() {
    env e1;
    env e2;
    SponsorPaymaster.UserOperation userOp1;
    SponsorPaymaster.UserOperation userOp2;
    IPaymaster.PostOpMode mode;
    bytes32 userOpHash1;
    bytes32 userOpHash2;
    uint256 maxCost1;
    uint256 maxCost2;

    bytes context1; address account1; address wallet1; uint256 actualCost1; uint256 maxFee1;
    bytes context2; address account2; address wallet2; uint256 actualCost2; uint256 maxFee2;
    
    storage initState = lastStorage;
    /// First attempt (validate + postOp)
    context1, _ = validatePaymasterUserOp(e1, userOp1, userOpHash1, maxCost1) at initState;
    account1, wallet1, maxFee1, _ = contextDecode(context1);
    postOp(e1, mode, context1, actualCost1);
    
    /// Second user (validate + postOp)
    context2, _ = validatePaymasterUserOp(e2, userOp2, userOpHash2, maxCost2) at initState;
    account2, wallet2, maxFee2, _ = contextDecode(context2);
    postOp(e2, mode, context2, actualCost2);

    /// Currently we only consider different senders (wallet owners).
    /// If the apps are equal, then the total limit could be reached.
    require WalletOwners(wallet1, 0) != WalletOwners(wallet2, 0);
    mathint ethMaxCost = (maxCost1 + COST_OF_POST() * userOp1.maxFeePerGas);
    mathint ethActualCost = (actualCost1 + COST_OF_POST() * maxFee1);
    /// Assumption: app deposits enough ETH for transactions.
    require account1 == account2 => to_mathint(balances(account1)) >= ethMaxCost;
    require account1 == account2 => to_mathint(balances(account1)) >= ethActualCost;
    /// No overflow
    require contractSpent(account1) + ethActualCost <= max_uint256;
    /// First attempt - again (validate + postOp)
    validatePaymasterUserOp@withrevert(e1, userOp1, userOpHash1, maxCost1);
    bool validateReverted = lastReverted;
    postOp@withrevert(e1, mode, context1, actualCost1);
    bool postOpReverted = lastReverted;

    assert !(validateReverted || postOpReverted);
}

/// @title No operation can front-run validatePaymasterUserOp() and make it revert.
rule noOperationFrontRunsValidate(method f) 
filtered{f -> !viewOrUpgrade(f) &&  
    f.selector != sig:initialize(address,address,address).selector &&
    f.selector != sig:validatePaymasterUserOp(SponsorPaymaster.UserOperation,bytes32,uint256).selector && 
    f.selector != sig:setUserOpMaxCost(uint256).selector}
{    
    env e1; calldataarg args1;
    env e2; calldataarg args2;
    storage initState = lastStorage;

    bytes context;
    context, _ = validatePaymasterUserOp(e1, args1) at initState;
    address app;
    app, _, _, _ = contextDecode(context);

    f(e2, args2) at initState;
    validatePaymasterUserOp@withrevert(e1, args1);
    bool reverted = lastReverted;

    if(f.selector == sig:postOp(IPaymaster.PostOpMode,bytes,uint256).selector) {
        assert e2.msg.sender == entryPoint();
    }
    else if(f.selector == sig:unlockTokenDeposit().selector) {
        assert reverted => app == e2.msg.sender;
    }
    else {
        assert !reverted;
    }   

    assert true;
}

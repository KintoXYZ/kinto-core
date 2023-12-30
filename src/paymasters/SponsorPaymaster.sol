// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

/* solhint-disable reason-string */

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@aa/core/BasePaymaster.sol';
import '@aa/core/UserOperationLib.sol';
import '../interfaces/ISponsorPaymaster.sol';
import '../interfaces/IKintoWallet.sol';

/**
 * An ETH-based paymaster that accepts ETH deposits
 * The deposit is only a safeguard: the user pays with his ETH deposited in the entry point if any.
 * The deposit is locked for the current block: the user must issue unlockTokenDeposit() to be allowed to withdraw
 *  (but can't use the deposit for this or further operations)
 *
 * paymasterAndData holds the paymaster address followed by the token address to use.
 */
contract SponsorPaymaster is Initializable, BasePaymaster, UUPSUpgradeable, ReentrancyGuard, ISponsorPaymaster {

    using UserOperationLib for UserOperation;
    using SafeERC20 for IERC20;

    //calculated cost of the postOp
    uint256 constant public COST_OF_POST = 60_000;
    uint256 constant public MAX_COST_OF_VERIFICATION = 180_000;
    uint256 constant public MAX_COST_OF_PREVERIFICATION = 50_000;
    uint256 constant public MAX_COST_OF_USEROP = 3e15; // 0.03 ETH

    uint256 constant public RATE_LIMIT_PERIOD = 1 minutes;
    uint256 constant public RATE_LIMIT_THRESHOLD_SINGLE = 10;
    uint256 constant public RATE_LIMIT_THRESHOLD_TOTAL = 50;

    uint256 constant public GAS_LIMIT_PERIOD = 30 days;
    uint256 constant public GAS_LIMIT_THRESHOLD_SINGLE = 1e16; // 0.01 ETH

    mapping(address => uint256) public balances;
    mapping(address => uint256) public contractSpent; // keeps track of total gas consumption by contract
    mapping(address => uint256) public unlockBlock;
    // A mapping for rate limiting data: account => contract => RateLimitData
    mapping(address => mapping(address => ISponsorPaymaster.RateLimitData)) public rateLimit;
    mapping(address => mapping(address => ISponsorPaymaster.RateLimitData)) public costLimit;
    mapping(address => ISponsorPaymaster.RateLimitData) public totalRateLimit;

    // ========== Constructor & Upgrades ============

    constructor(IEntryPoint __entryPoint) BasePaymaster(__entryPoint) {
        _disableInitializers();
    }

    /**
     * @dev The _entryPoint member is immutable, to reduce gas consumption.  To upgrade EntryPoint,
     * a new implementation of SimpleAccount must be deployed with the new EntryPoint address, then upgrading
     * the implementation by calling `upgradeTo()`
     */
    function initialize(address _owner) external virtual initializer {
        __UUPSUpgradeable_init();
        _transferOwnership(_owner);
        // unlocks owner
        unlockBlock[_owner] = block.number;
    }

    /**
     * @dev Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the implementation is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override {
        require(msg.sender == owner(), 'SP: not owner');
        (newImplementation);
    }

    // ========== Deposit Mgmt ============

    /**
     * ETH value that a specific account can use to pay for gas.
     * Note depositing the tokens is equivalent to transferring them to the "account" - only the account can later
     *  use them - either as gas, or using withdrawTo()
     *
     * @param account the account to deposit for.
     * msg.value the amount of token to deposit.
     */
    function addDepositFor(address account) payable external override {
        require(msg.value > 0, 'SP: requires a deposit');
        //(sender must have approval for the paymaster)
        balances[account] += msg.value;
        if (msg.sender == account) {
            lockTokenDeposit();
        }
        deposit();
    }

    /**
     * Unlocks deposit, so that it can be withdrawn.
     * can't be called in the same block as withdrawTo()
     */
    function unlockTokenDeposit() public override {
        unlockBlock[msg.sender] = block.number;
    }

    /**
     * Lock the ETH deposited for this account so they can be used to pay for gas.
     * after calling unlockTokenDeposit(), the account can't use this paymaster until the deposit is locked.
     */
    function lockTokenDeposit() public override {
        unlockBlock[msg.sender] = 0;
    }

    /**
     * Withdraw ETH
     * can only be called after unlock() is called in a previous block.
     * @param target address to send to
     * @param amount amount to withdraw
     */
    function withdrawTokensTo(address target, uint256 amount) external override nonReentrant() {
        require(
            balances[msg.sender] >= amount &&
            unlockBlock[msg.sender] != 0 && block.number > unlockBlock[msg.sender],
            'SP: must unlockTokenDeposit'
        );
        balances[msg.sender] -= amount;
        entryPoint.withdrawTo(payable(target), amount);
    }

    /********* Viewers & validation *********/

    /**
     * Return the deposit info for the account
     * @return amount - the amount of given token deposited to the Paymaster.
     * @return _unlockBlock - the block height at which the deposit can be withdrawn.
     */
    function depositInfo(address account) external view returns (uint256 amount, uint256 _unlockBlock) {
        amount = balances[account];
        _unlockBlock = unlockBlock[account];
    }

    /**
     * Return the current user limits for the app
     * @param user - the user account
     * @param app - the app contract
     * @return operationCount - the number of operations performed by the user for the app
     *         lastOperationTime - the timestamp of when the tx threshold was last started
     *         costLimit - the maximum cost of operations for the user for the app
     *         lastOperationTime - the timestamp of when the gas threshold was last started
     */
    function appUserLimit(address user,
        address app) external view override returns (uint256, uint256, uint256, uint256) {
        return (
            rateLimit[user][app].operationCount,
            rateLimit[user][app].lastOperationTime,
            costLimit[user][app].ethCostCount,
            costLimit[user][app].lastOperationTime
        );
    }

    /**
     * Validate the request from the sender to fund it.
     * The sender should have enough txs and gas left to be gasless.
     * The contract developer funds the contract for its users and rate limits the app.
     */
    function _validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal view override returns (bytes memory context, uint256 validationData) {
        (userOpHash);
        // verificationGasLimit is dual-purposed, as gas limit for postOp. make sure it is high enough
        require(userOp.verificationGasLimit >= COST_OF_POST && userOp.verificationGasLimit <= MAX_COST_OF_VERIFICATION,
            'SP: gas outside of range for postOp');
        require(userOp.preVerificationGas <= MAX_COST_OF_PREVERIFICATION,
            'SP: gas too high for verification');
        bytes calldata paymasterAndData = userOp.paymasterAndData;
        require(paymasterAndData.length == 20, 'SP: paymasterAndData must contain only paymaster');

        // Get the contract called from calldata
        address targetAccount =  _getLastTargetContract(userOp.sender, userOp.callData);
        uint256 gasPriceUserOp = userOp.gasPrice();
        uint256 ethMaxCost = (maxCost + COST_OF_POST * gasPriceUserOp);
        require(ethMaxCost <= MAX_COST_OF_USEROP, 'SP: gas too high for user op');

        // Check app rate limiting
        ISponsorPaymaster.RateLimitData memory data = rateLimit[userOp.sender][targetAccount];
        if (block.timestamp < data.lastOperationTime + RATE_LIMIT_PERIOD) {
            require(data.operationCount < RATE_LIMIT_THRESHOLD_SINGLE, 'SP: App Rate limit exceeded');
        }

        // Check Kinto Gas limit app
        ISponsorPaymaster.RateLimitData memory gasLimit = costLimit[userOp.sender][targetAccount];
        if (block.timestamp < gasLimit.lastOperationTime + GAS_LIMIT_PERIOD) {
            require((gasLimit.ethCostCount + ethMaxCost) <= GAS_LIMIT_THRESHOLD_SINGLE,
                'SP: Kinto Gas App limit exceeded');
        } else {
            // First time need to be checked
            require(ethMaxCost <= GAS_LIMIT_THRESHOLD_SINGLE, 'SP: Kinto Gas App limit exceeded');
        }

        // Check Kinto rate limiting
        ISponsorPaymaster.RateLimitData memory globalData = totalRateLimit[userOp.sender];
        if (block.timestamp < globalData.lastOperationTime + RATE_LIMIT_PERIOD) {
            require(globalData.operationCount < RATE_LIMIT_THRESHOLD_TOTAL, 'SP: Kinto Rate limit exceeded');
        } 

        require(unlockBlock[targetAccount] == 0, 'SP: deposit not locked');
        require(balances[targetAccount] >= maxCost, 'SP: deposit too low');
        return (abi.encode(targetAccount, userOp.sender, gasPriceUserOp), 0);
    }

    /**
     * perform the post-operation to charge the account contract for the gas.
     */
    function _postOp(PostOpMode /* mode */, bytes calldata context, uint256 actualGasCost) internal override {
        (address account, address userAccount, uint256 gasPricePostOp) =
            abi.decode(context, (address, address, uint256));
        //use same conversion rate as used for validation.
        uint256 ethCost = (actualGasCost + COST_OF_POST * gasPricePostOp);
        balances[account] -= ethCost;
        contractSpent[account] += ethCost;
        // Updates app rate limiting
        ISponsorPaymaster.RateLimitData storage appTxLimit = rateLimit[userAccount][account];
        if (block.timestamp > appTxLimit.lastOperationTime + RATE_LIMIT_PERIOD) {
            appTxLimit.lastOperationTime = block.timestamp;
            appTxLimit.operationCount = 1;
        } else {
            appTxLimit.operationCount += 1;
        }
        // App gas limit
        ISponsorPaymaster.RateLimitData storage costApp = costLimit[userAccount][account];
        if (block.timestamp > costApp.lastOperationTime + GAS_LIMIT_PERIOD) {
            costApp.lastOperationTime = block.timestamp;
            costApp.ethCostCount = ethCost;
        } else {
            costApp.ethCostCount += ethCost;
        }
        // Global network rate limit
        ISponsorPaymaster.RateLimitData storage globalTxLimit = totalRateLimit[userAccount];
        if (block.timestamp > globalTxLimit.lastOperationTime + RATE_LIMIT_PERIOD) {
            globalTxLimit.lastOperationTime = block.timestamp;
            globalTxLimit.operationCount = 1;
        } else {
            globalTxLimit.operationCount += 1;
        }
    }

    // Function to extract the first target contract
    function _getLastTargetContract(address sender, bytes calldata callData) private pure returns (address lastTargetContract) {
        // Extract the function selector from the callData
        bytes4 selector = bytes4(callData[:4]);

        // Compare the selector with the known function selectors
        if (selector == IKintoWallet.executeBatch.selector) {
            // Decode callData for executeBatch
            (address[] memory targetContracts,,) = abi.decode(callData[4:], (address[], uint256[], bytes[]));
            lastTargetContract = targetContracts[targetContracts.length - 1];
            for (uint256 i = 0; i < targetContracts.length - 1; i++) {
                if (targetContracts[i] != lastTargetContract && targetContracts[i] != sender) {
                    revert('SP: executeBatch must come from same contract or sender wallet');
                }
            }
        } else if (selector == IKintoWallet.execute.selector) {
            // Decode callData for execute
            (address targetContract,,) = abi.decode(callData[4:], (address, uint256, bytes));
            lastTargetContract = targetContract;
        } else {
            // Handle unknown function or error
            revert('SP: Unknown function selector');
        }
    }
    
}
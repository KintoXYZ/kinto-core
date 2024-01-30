// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@aa/core/BasePaymaster.sol";

import "../interfaces/ISponsorPaymaster.sol";
import "../interfaces/IKintoAppRegistry.sol";
import "../interfaces/IKintoWallet.sol";
import "../interfaces/IKintoID.sol";

/**
 * An ETH-based paymaster that accepts ETH deposits
 * The deposit is only a safeguard: the user pays with his ETH deposited in the entry point if any.
 * The deposit is locked for the current block: the user must issue unlockTokenDeposit() to be allowed to withdraw
 *  (but can't use the deposit for this or further operations)
 *
 * paymasterAndData holds the paymaster address followed by the token address to use.
 */
contract SponsorPaymaster is Initializable, BasePaymaster, UUPSUpgradeable, ReentrancyGuard, ISponsorPaymaster {
    using SafeERC20 for IERC20;

    // calculated cost of the postOp
    uint256 public constant COST_OF_POST = 200_000;
    uint256 public constant MAX_COST_OF_VERIFICATION = 230_000;
    uint256 public constant MAX_COST_OF_PREVERIFICATION = 110_000;

    uint256 public constant RATE_LIMIT_PERIOD = 1 minutes;
    uint256 public constant RATE_LIMIT_THRESHOLD_TOTAL = 50;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public contractSpent; // keeps track of total gas consumption by contract
    mapping(address => uint256) public unlockBlock;

    // rate & cost limits per user per app: user => app => RateLimitData
    mapping(address => mapping(address => ISponsorPaymaster.RateLimitData)) public rateLimit;
    mapping(address => mapping(address => ISponsorPaymaster.RateLimitData)) public costLimit;

    // rate limit across apps: user => RateLimitData
    mapping(address => ISponsorPaymaster.RateLimitData) public globalRateLimit;

    IKintoAppRegistry public override appRegistry;
    IKintoID public kintoID;

    uint256 public userOpMaxCost;

    // ========== Events ============

    event AppRegistrySet(address oldRegistry, address newRegistry);
    event UserOpMaxCostSet(uint256 oldUserOpMaxCost, uint256 newUserOpMaxCost);

    // ========== Constructor & Upgrades ============

    constructor(IEntryPoint __entryPoint) BasePaymaster(__entryPoint) {
        _disableInitializers();
    }

    /**
     * @dev The _entryPoint member is immutable, to reduce gas consumption.  To upgrade EntryPoint,
     * a new implementation of SimpleAccount must be deployed with the new EntryPoint address, then upgrading
     * the implementation by calling `upgradeTo()`
     */
    function initialize(address _owner, IKintoAppRegistry _appRegistry, IKintoID _kintoID)
        external
        virtual
        initializer
    {
        __UUPSUpgradeable_init();
        _transferOwnership(_owner);

        kintoID = _kintoID;
        appRegistry = _appRegistry;
        unlockBlock[_owner] = block.number; // unlocks owner
    }

    /**
     * @dev Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the implementation is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override {
        require(msg.sender == owner(), "SP: not owner");
        (newImplementation);
    }

    // ========== Deposit Mgmt ============

    /**
     * ETH value that a specific account can use to pay for gas.
     * Note depositing the tokens is equivalent to transferring them to the "account" - only the account can later
     * use them - either as gas, or using withdrawTo()
     *
     * @param account the account to deposit for.
     * msg.value the amount of token to deposit.
     */
    function addDepositFor(address account) external payable override {
        require(msg.value > 0, "SP: requires a deposit");
        require(kintoID.isKYC(msg.sender), "SP: sender KYC required");
        if (account.code.length == 0 && !kintoID.isKYC(account)) revert("SP: account KYC required");

        // sender must have approval for the paymaster
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
    function withdrawTokensTo(address target, uint256 amount) external override nonReentrant {
        require(
            balances[msg.sender] >= amount && unlockBlock[msg.sender] != 0 && block.number > unlockBlock[msg.sender],
            "SP: must unlockTokenDeposit"
        );
        balances[msg.sender] -= amount;
        entryPoint.withdrawTo(payable(target), amount);
    }

    /* =============== Setters & Getters ============= */

    /**
     * Return the deposit info for the account
     * @return amount - the amount of given token deposited to the Paymaster.
     * @return _unlockBlock - the block height at which the deposit can be withdrawn.
     */
    function depositInfo(address account) external view returns (uint256 amount, uint256 _unlockBlock) {
        return (balances[account], unlockBlock[account]);
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
    function appUserLimit(address user, address app)
        external
        view
        override
        returns (uint256, uint256, uint256, uint256)
    {
        return (
            rateLimit[user][app].operationCount,
            rateLimit[user][app].lastOperationTime,
            costLimit[user][app].ethCostCount,
            costLimit[user][app].lastOperationTime
        );
    }

    /**
     * @dev Set the app registry
     * @param _newRegistry address of the app registry
     */
    function setAppRegistry(address _newRegistry) external override onlyOwner {
        require(_newRegistry != address(0), "SP: new registry cannot be 0");
        require(_newRegistry != address(appRegistry), "SP: new registry cannot be the same");
        emit AppRegistrySet(address(appRegistry), _newRegistry);
        appRegistry = IKintoAppRegistry(_newRegistry);
    }

    /**
     * @dev Set the max cost of a user operation
     * @param _newUserOpMaxCost max cost of a user operation
     */
    function setUserOpMaxCost(uint256 _newUserOpMaxCost) external onlyOwner {
        emit UserOpMaxCostSet(userOpMaxCost, _newUserOpMaxCost);
        userOpMaxCost = _newUserOpMaxCost;
    }

    /* =============== AA overrides ============= */

    /**
     * @notice Validates the request from the sender to fund it.
     * @dev sender should have enough txs and gas left to be gasless.
     * @dev contract developer funds the contract for its users and rate limits the app.
     */
    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        internal
        view
        override
        returns (bytes memory context, uint256 validationData)
    {
        (userOpHash);

        // verificationGasLimit is dual-purposed, as gas limit for postOp. make sure it is high enough
        require(
            userOp.verificationGasLimit >= COST_OF_POST && userOp.verificationGasLimit <= MAX_COST_OF_VERIFICATION,
            "SP: gas outside of range for postOp"
        );
        require(userOp.preVerificationGas <= MAX_COST_OF_PREVERIFICATION, "SP: gas too high for verification");
        require(userOp.paymasterAndData.length == 20, "SP: paymasterAndData must contain only paymaster");

        // use maxFeePerGas for conservative estimation of gas cost
        uint256 gasPriceUserOp = userOp.maxFeePerGas;
        uint256 ethMaxCost = (maxCost + COST_OF_POST * gasPriceUserOp);
        require(ethMaxCost <= userOpMaxCost, "SP: gas too high for user op");

        address sponsor = appRegistry.getSponsor(_decodeCallData(userOp.callData));
        require(unlockBlock[sponsor] == 0, "SP: deposit not locked");
        require(balances[sponsor] >= ethMaxCost, "SP: deposit too low");
        return (abi.encode(sponsor, userOp.sender, userOp.maxFeePerGas, userOp.maxPriorityFeePerGas), 0);
    }

    /**
     * @notice performs the post-operation to charge the account contract for the gas.
     */
    function _postOp(PostOpMode, /* mode */ bytes calldata context, uint256 actualGasCost) internal override {
        (address account, address userAccount, uint256 maxFeePerGas, uint256 maxPriorityFeePerGas) =
            abi.decode(context, (address, address, uint256, uint256));

        // calculate actual gas cost using block.basefee and maxPriorityFeePerGas
        uint256 actualGasPrice = _min(maxFeePerGas, maxPriorityFeePerGas + block.basefee);
        uint256 ethCost = (actualGasCost + COST_OF_POST * actualGasPrice);
        balances[account] -= ethCost;
        contractSpent[account] += ethCost;

        // update global rate limit
        ISponsorPaymaster.RateLimitData storage globalTxLimit = globalRateLimit[userAccount];
        if (block.timestamp > globalTxLimit.lastOperationTime + RATE_LIMIT_PERIOD) {
            globalTxLimit.lastOperationTime = block.timestamp;
            globalTxLimit.operationCount = 1;
        } else {
            globalTxLimit.operationCount += 1;
        }

        uint256[4] memory appLimits = appRegistry.getContractLimits(account);

        // update app rate limiting
        ISponsorPaymaster.RateLimitData storage appTxLimit = rateLimit[userAccount][account];
        if (block.timestamp > appTxLimit.lastOperationTime + appLimits[0]) {
            appTxLimit.lastOperationTime = block.timestamp;
            appTxLimit.operationCount = 1;
        } else {
            appTxLimit.operationCount += 1;
        }

        // app gas limit
        ISponsorPaymaster.RateLimitData storage costApp = costLimit[userAccount][account];
        if (block.timestamp > costApp.lastOperationTime + appLimits[2]) {
            costApp.lastOperationTime = block.timestamp;
            costApp.ethCostCount = ethCost;
        } else {
            costApp.ethCostCount += ethCost;
        }

        // check limits after updating
        _checkLimits(userAccount, account, ethCost);
    }

    /* =============== Internal methods ============= */

    function _checkLimits(address sender, address targetAccount, uint256 ethMaxCost) internal view {
        // global rate limit check
        ISponsorPaymaster.RateLimitData memory globalData = globalRateLimit[sender];
        require(
            block.timestamp >= globalData.lastOperationTime + RATE_LIMIT_PERIOD
                || globalData.operationCount <= RATE_LIMIT_THRESHOLD_TOTAL,
            "SP: Kinto Rate limit exceeded"
        );

        // app rate limit check
        uint256[4] memory appLimits = appRegistry.getContractLimits(targetAccount);
        ISponsorPaymaster.RateLimitData memory appData = rateLimit[sender][targetAccount];

        require(
            block.timestamp >= appData.lastOperationTime + appLimits[0] || appData.operationCount <= appLimits[1],
            "SP: App Rate limit exceeded"
        );

        // app gas limit check
        ISponsorPaymaster.RateLimitData memory gasData = costLimit[sender][targetAccount];
        require(
            block.timestamp >= gasData.lastOperationTime + appLimits[2]
                || (gasData.ethCostCount + ethMaxCost) <= appLimits[3],
            "SP: Kinto Gas App limit exceeded"
        );
    }

    /**
     * @notice extracts `target` contract from callData
     * @dev the last op on a batch MUST always be a contract whose sponsor is the one we want to
     * bear with the gas cost of all ops
     * @dev this is very similar to KintoWallet._decodeCallData, consider unifying
     */
    function _decodeCallData(bytes calldata callData) private pure returns (address target) {
        bytes4 selector = bytes4(callData[:4]); // extract the function selector from the callData

        if (selector == IKintoWallet.executeBatch.selector) {
            // decode executeBatch callData
            (address[] memory targets,,) = abi.decode(callData[4:], (address[], uint256[], bytes[]));
            if (targets.length == 0) return address(0);

            // target is the last element of the batch
            target = targets[targets.length - 1];
        } else if (selector == IKintoWallet.execute.selector) {
            (target,,) = abi.decode(callData[4:], (address, uint256, bytes)); // decode execute callData
        }
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract SponsorPaymasterV4 is SponsorPaymaster {
    constructor(IEntryPoint __entryPoint) SponsorPaymaster(__entryPoint) {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "@aa/interfaces/IPaymaster.sol";
import {IEntryPoint} from "@aa/core/BaseAccount.sol";

import {ISponsorPaymaster} from "@kinto-core/interfaces/ISponsorPaymaster.sol";
import {IKintoAppRegistry} from "@kinto-core/interfaces/IKintoAppRegistry.sol";
import {IKintoWallet} from "@kinto-core/interfaces/IKintoWallet.sol";
import {IKintoID} from "@kinto-core/interfaces/IKintoID.sol";
import {IKintoWalletFactory} from "@kinto-core/interfaces/IKintoWalletFactory.sol";

/**
 * Helper class for creating a paymaster.
 * provides helper methods for staking.
 * Validates that the postOp is called only by the entryPoint.
 */
abstract contract BasePaymaster is IPaymaster, Ownable {
    IEntryPoint public immutable entryPoint;

    constructor(IEntryPoint _entryPoint) {
        entryPoint = _entryPoint;
    }

    /// @inheritdoc IPaymaster
    function validatePaymasterUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        external
        override
        returns (bytes memory context, uint256 validationData)
    {
        _requireFromEntryPoint();
        return _validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    /**
     * Validate a user operation.
     * @param userOp     - The user operation.
     * @param userOpHash - The hash of the user operation.
     * @param maxCost    - The maximum cost of the user operation.
     */
    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        internal
        virtual
        returns (bytes memory context, uint256 validationData);

    /// @inheritdoc IPaymaster
    function postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) external override {
        _requireFromEntryPoint();
        _postOp(mode, context, actualGasCost);
    }

    /**
     * Post-operation handler.
     * (verified to be called only through the entryPoint)
     * @dev If subclass returns a non-empty context from validatePaymasterUserOp,
     *      it must also implement this method.
     * @param mode          - Enum with the following options:
     *                        opSucceeded - User operation succeeded.
     *                        opReverted  - User op reverted. still has to pay for gas.
     *                        postOpReverted - User op succeeded, but caused postOp (in mode=opSucceeded) to revert.
     *                                         Now this is the 2nd call, after user's op was deliberately reverted.
     * @param context       - The context value returned by validatePaymasterUserOp
     * @param actualGasCost - Actual gas used so far (without this postOp call).
     */
    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) internal virtual {
        (mode, context, actualGasCost); // unused params
        // subclass must override this method if validatePaymasterUserOp returns a context
        revert("must override");
    }

    /**
     * Add stake for this paymaster.
     * This method can also carry eth value to add to the current stake.
     * @param unstakeDelaySec - The unstake delay for this paymaster. Can only be increased.
     */
    function addStake(uint32 unstakeDelaySec) external payable onlyOwner {
        entryPoint.addStake{value: msg.value}(unstakeDelaySec);
    }

    /**
     * Return current paymaster's deposit on the entryPoint.
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint.balanceOf(address(this));
    }

    /**
     * Unlock the stake, in order to withdraw it.
     * The paymaster can't serve requests once unlocked, until it calls addStake again
     */
    function unlockStake() external onlyOwner {
        entryPoint.unlockStake();
    }

    /**
     * Withdraw the entire paymaster's stake.
     * stake must be unlocked first (and then wait for the unstakeDelay to be over)
     * @param withdrawAddress - The address to send withdrawn value.
     */
    function withdrawStake(address payable withdrawAddress) external onlyOwner {
        entryPoint.withdrawStake(withdrawAddress);
    }

    /**
     * Validate the call is made from a valid entrypoint
     */
    function _requireFromEntryPoint() internal virtual {
        require(msg.sender == address(entryPoint), "Sender not EntryPoint");
    }
}

/**
 * @notice An ETH-based paymaster that accepts ETH deposits
 * The deposit is only a safeguard: the user pays with his ETH deposited in the entry point if any.
 * The deposit is locked for the current block: the user must issue unlockTokenDeposit() to be allowed to withdraw
 *  (but can't use the deposit for this or further operations)
 *
 * @dev paymaster defines global, per-app, and per-user limits on operation frequency (rate limit) and accumulated gas costs (gas limit).
 * - Global rate limit controls the total number of operations within a set period across all users and apps.
 * - App rate limit restricts the number of operations a user can perform on a specific app within a certain timeframe.
 * - App gas limit monitors the accumulated gas costs per user per app, preventing exceeding a specified gas threshold.
 *
 * `paymasterAndData` holds the paymaster address followed by the token address to use.
 */
contract SponsorPaymaster is Initializable, BasePaymaster, UUPSUpgradeable, ReentrancyGuard, ISponsorPaymaster {
    using SafeERC20 for IERC20;

    /* ============ Constants & Immutables ============ */

    // calculated cost of the postOp
    uint256 public constant COST_OF_POST = 200_000;
    uint256 public constant MAX_COST_OF_VERIFICATION = 530_000;
    uint256 public constant MAX_COST_OF_PREVERIFICATION = 4_000_000;

    uint256 public constant RATE_LIMIT_PERIOD = 1 minutes;
    uint256 public constant RATE_LIMIT_THRESHOLD_TOTAL = 50;

    /// @notice The KintoWalletFactory contract
    IKintoWalletFactory public immutable override walletFactory;

    /* ============ State Variables ============ */

    mapping(address => uint256) public balances;
    mapping(address => uint256) public contractSpent; // keeps track of total gas consumption by contract
    mapping(address => uint256) public unlockBlock;

    // rate & cost limits per user per app: user => app => RateLimitData
    // slither-disable-next-line uninitialized-state
    mapping(address => mapping(address => ISponsorPaymaster.RateLimitData)) public rateLimit;
    // slither-disable-next-line uninitialized-state
    mapping(address => mapping(address => ISponsorPaymaster.RateLimitData)) public costLimit;

    // rate limit across apps: user => RateLimitData
    // slither-disable-next-line uninitialized-state
    mapping(address => ISponsorPaymaster.RateLimitData) public globalRateLimit;

    IKintoAppRegistry public override appRegistry;
    IKintoID public kintoID;

    uint256 public userOpMaxCost;

    // ========== Events ============

    event AppRegistrySet(address oldRegistry, address newRegistry);
    event UserOpMaxCostSet(uint256 oldUserOpMaxCost, uint256 newUserOpMaxCost);

    // ========== Constructor & Upgrades ============

    constructor(IEntryPoint __entryPoint, IKintoWalletFactory _walletFactory) BasePaymaster(__entryPoint) {
        _disableInitializers();
        walletFactory = _walletFactory;
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
        userOpMaxCost = 0.03 ether;
        unlockBlock[_owner] = block.number; // unlocks owner
    }

    /**
     * @dev Authorize the upgrade. Only by an owner.
     * @param newImplementation address of the new implementation
     */
    // This function is called by the proxy contract when the implementation is upgraded
    function _authorizeUpgrade(address newImplementation) internal view override {
        if (msg.sender != owner()) revert OnlyOwner();
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
        if (msg.value == 0) revert InvalidAmount();
        if (!kintoID.isKYC(msg.sender) && msg.sender != owner() && walletFactory.walletTs(msg.sender) == 0) {
            revert SenderKYCRequired();
        }
        if (account.code.length == 0 && !kintoID.isKYC(account)) revert AccountKYCRequired();

        // sender must have approval for the paymaster
        balances[account] += msg.value;
        if (msg.sender == account) {
            lockTokenDeposit();
        }
        entryPoint.depositTo{value: msg.value}(address(this));
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
     * Withdraw ETH can only be called after unlock() is called in a previous block.
     * @param target address to send to
     * @param amount amount to withdraw
     */
    function withdrawTokensTo(address target, uint256 amount) external override nonReentrant {
        if (balances[msg.sender] < amount || unlockBlock[msg.sender] == 0 || block.number <= unlockBlock[msg.sender]) {
            revert TokenDepositLocked();
        }
        if (target == address(0) || target.code.length > 0) revert InvalidTarget();
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
     * @param wallet - the wallet account
     * @param app - the app contract
     * @return operationCount - the number of operations performed by the user for the app
     *         lastOperationTime - the timestamp of when the tx threshold was last started
     *         costLimit - the maximum cost of operations for the user for the app
     *         lastOperationTime - the timestamp of when the gas threshold was last started
     */
    function appUserLimit(address wallet, address app)
        external
        view
        override
        returns (uint256, uint256, uint256, uint256)
    {
        address userAccount = IKintoWallet(wallet).owners(0);
        return (
            rateLimit[userAccount][app].operationCount,
            rateLimit[userAccount][app].lastOperationTime,
            costLimit[userAccount][app].ethCostCount,
            costLimit[userAccount][app].lastOperationTime
        );
    }

    /**
     * @dev Set the app registry
     * @param _newRegistry address of the app registry
     */
    function setAppRegistry(address _newRegistry) external override onlyOwner {
        if (_newRegistry == address(0)) revert InvalidRegistry();
        if (_newRegistry == address(appRegistry)) revert InvalidRegistry();
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
        if (userOp.verificationGasLimit < COST_OF_POST || userOp.verificationGasLimit > MAX_COST_OF_VERIFICATION) {
            revert GasOutsideRangeForPostOp();
        }
        if (userOp.preVerificationGas > MAX_COST_OF_PREVERIFICATION) revert GasTooHighForVerification();
        if (userOp.paymasterAndData.length != 20) revert PaymasterAndDataLengthInvalid();

        // use maxFeePerGas for conservative estimation of gas cost
        uint256 gasPriceUserOp = userOp.maxFeePerGas;
        uint256 ethMaxCost = (maxCost + COST_OF_POST * gasPriceUserOp);
        if (ethMaxCost > userOpMaxCost) revert GasTooHighForUserOp();

        address sponsor = appRegistry.getApp(_decodeCallData(userOp.callData));
        if (unlockBlock[sponsor] != 0) revert DepositNotLocked();
        if (balances[sponsor] < ethMaxCost) revert DepositTooLow();
        return (abi.encode(sponsor, userOp.sender, userOp.maxFeePerGas, userOp.maxPriorityFeePerGas), 0);
    }

    /**
     * @notice performs the post-operation to charge the sponsor contract for the gas.
     */
    function _postOp(PostOpMode, /* mode */ bytes calldata context, uint256 actualGasCost) internal override {
        (address sponsor, address kintoWallet, uint256 maxFeePerGas, uint256 maxPriorityFeePerGas) =
            abi.decode(context, (address, address, uint256, uint256));
        address user = IKintoWallet(kintoWallet).owners(0); // use owner because a person can have many wallets

        // update global rate limit
        ISponsorPaymaster.RateLimitData storage globalTxLimit = globalRateLimit[user];
        if (block.timestamp > globalTxLimit.lastOperationTime + RATE_LIMIT_PERIOD) {
            globalTxLimit.lastOperationTime = block.timestamp;
            globalTxLimit.operationCount = 1;
        } else {
            globalTxLimit.operationCount += 1;
        }

        // app limits
        uint256[4] memory appLimits = appRegistry.getContractLimits(sponsor);

        // update app rate limiting
        ISponsorPaymaster.RateLimitData storage appTxLimit = rateLimit[user][sponsor];
        if (block.timestamp > appTxLimit.lastOperationTime + appLimits[0]) {
            appTxLimit.lastOperationTime = block.timestamp;
            appTxLimit.operationCount = 1;
        } else {
            appTxLimit.operationCount += 1;
        }

        // app gas limit

        // calculate actual gas cost using block.basefee and maxPriorityFeePerGas
        uint256 actualGasPrice = _min(maxFeePerGas, maxPriorityFeePerGas + block.basefee);
        uint256 ethCost = (actualGasCost + COST_OF_POST * actualGasPrice);
        balances[sponsor] -= ethCost;
        contractSpent[sponsor] += ethCost;

        // update app gas limiting
        ISponsorPaymaster.RateLimitData storage costApp = costLimit[user][sponsor];
        if (block.timestamp > costApp.lastOperationTime + appLimits[2]) {
            costApp.lastOperationTime = block.timestamp;
            costApp.ethCostCount = ethCost;
        } else {
            costApp.ethCostCount += ethCost;
        }

        // check limits after updating
        _checkLimits(user, sponsor, ethCost);
    }

    /* =============== Internal methods ============= */

    /**
     * @notice ensures the operation rate and costs are within the user's limits for a given sponsor (app)
     */
    function _checkLimits(address user, address sponsor, uint256 /* ethMaxCost */ ) internal view {
        // global rate limit check
        ISponsorPaymaster.RateLimitData memory limit = globalRateLimit[user];
        if (
            block.timestamp < limit.lastOperationTime + RATE_LIMIT_PERIOD
                && limit.operationCount > RATE_LIMIT_THRESHOLD_TOTAL
        ) revert KintoRateLimitExceeded();

        // app rate limit check
        uint256[4] memory appLimits = appRegistry.getContractLimits(sponsor);
        limit = rateLimit[user][sponsor];

        if (block.timestamp < limit.lastOperationTime + appLimits[0] && limit.operationCount > appLimits[1]) {
            revert AppRateLimitExceeded();
        }

        // app gas limit check
        limit = costLimit[user][sponsor];
        if (block.timestamp < limit.lastOperationTime + appLimits[2] && limit.ethCostCount > appLimits[3]) {
            revert AppGasLimitExceeded();
        }
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

contract SponsorPaymasterV14 is SponsorPaymaster {
    constructor(IEntryPoint entryPoint, IKintoWalletFactory factory) SponsorPaymaster(entryPoint, factory) {}
}

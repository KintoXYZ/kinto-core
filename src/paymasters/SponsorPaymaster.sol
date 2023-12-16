// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

/* solhint-disable reason-string */

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@aa/core/BasePaymaster.sol';
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
    uint256 constant public COST_OF_POST = 35000;
    uint256 constant public RATE_LIMIT_PERIOD = 5 minutes;
    uint256 constant public RATE_LIMIT_THRESHOLD = 10;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public contractSpent; // keeps track of total gas consumption by contract
    mapping(address => uint256) public unlockBlock;
    // A mapping for rate limiting data: account => contract => RateLimitData
    mapping(address => mapping(address => ISponsorPaymaster.RateLimitData)) private rateLimit;

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
        require(msg.sender == owner(), 'SponsorPaymaster: not owner');
        (newImplementation);
    }

    /**
     * ETH value that a specific account can use to pay for gas.
     * Note depositing the tokens is equivalent to transferring them to the "account" - only the account can later
     *  use them - either as gas, or using withdrawTo()
     *
     * @param account the account to deposit for.
     * msg.value the amount of token to deposit.
     */
    function addDepositFor(address account) payable external override {
        require(msg.value > 0, 'requires a deposit');
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
            unlockBlock[msg.sender] != 0 && block.number > unlockBlock[msg.sender],
            'DepositPaymaster: must unlockTokenDeposit'
        );
        balances[msg.sender] -= amount;
        withdrawTo(payable(target), amount);
    }

    /*******************************
      Viewers *********************
    *******************************/

    /**
     * @return amount - the amount of given token deposited to the Paymaster.
     * @return _unlockBlock - the block height at which the deposit can be withdrawn.
     */
    function depositInfo(address account) external view returns (uint256 amount, uint256 _unlockBlock) {
        amount = balances[account];
        _unlockBlock = unlockBlock[account];
    }

    /**
     * Validate the request:
     * The sender should have enough deposit to pay the max possible cost.
     * Note that the sender's balance is not checked. If it fails to pay from its balance,
     * this deposit will be used to compensate the paymaster for the transaction.
     */
    function _validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal view override returns (bytes memory context, uint256 validationData) {
        (userOpHash);
        // verificationGasLimit is dual-purposed, as gas limit for postOp. make sure it is high enough
        require(userOp.verificationGasLimit > COST_OF_POST, 'DepositPaymaster: gas too low for postOp');
        bytes calldata paymasterAndData = userOp.paymasterAndData;
        require(paymasterAndData.length == 20, 'DepositPaymaster: paymasterAndData must contain only paymaster');
        // Get the contract called from calldata
        address targetAccount =  _getFirstTargetContract(userOp.callData);
        uint256 gasPriceUserOp = userOp.gasPrice();

        // Check rate limiting
        ISponsorPaymaster.RateLimitData memory data = rateLimit[userOp.sender][targetAccount];
        if (block.timestamp < data.lastOperationTime + RATE_LIMIT_PERIOD) {
            require(data.operationCount < RATE_LIMIT_THRESHOLD, "Rate limit exceeded");
        }

        require(unlockBlock[targetAccount] == 0, 'DepositPaymaster: deposit not locked');
        require(balances[targetAccount] >= maxCost, 'DepositPaymaster: deposit too low');
        return (abi.encode(targetAccount, userOp.sender, gasPriceUserOp), 0);
    }

    /**
     * perform the post-operation to charge the sender for the gas.
     * in normal mode, use transferFrom to withdraw enough tokens from the sender's balance.
     * in case the transferFrom fails, the _postOp reverts and the entryPoint will call it again,
     * this time in *postOpReverted* mode.
     * In this mode, we use the deposit to pay (which we validated to be large enough)
     */
    function _postOp(PostOpMode /* mode */, bytes calldata context, uint256 actualGasCost) internal override {
        (address account, address userAccount, uint256 gasPricePostOp) = abi.decode(context, (address, address, uint256));
        //use same conversion rate as used for validation.
        uint256 ethCost = (actualGasCost + COST_OF_POST * gasPricePostOp);
        balances[account] -= ethCost;
        contractSpent[account] += ethCost;
        // Updates rate limiting
        ISponsorPaymaster.RateLimitData storage data = rateLimit[userAccount][account];
        if (block.timestamp > data.lastOperationTime + RATE_LIMIT_PERIOD) {
            data.lastOperationTime = block.timestamp;
            data.operationCount = 1;
        } else {
            data.operationCount += 1;
        }
    }

    // Function to extract the first target contract
    function _getFirstTargetContract(bytes calldata callData) private pure returns (address firstTargetContract) {
        // Extract the function selector from the callData
        bytes4 selector = bytes4(callData[:4]);

        // Compare the selector with the known function selectors
        if (selector == IKintoWallet.executeBatch.selector) {
            // Decode callData for executeBatch
            (address[] memory targetContracts,,) = abi.decode(callData[4:], (address[], uint256[], bytes[]));
            firstTargetContract = targetContracts[0];
            // Contract only pays if all calls are to the same contract
            for (uint i = 0; i < targetContracts.length; i++) {
                require(targetContracts[i] == firstTargetContract, "executeBatch: all target contracts must be the same");
            }
        } else if (selector == IKintoWallet.execute.selector) {
            // Decode callData for execute
            (address targetContract,,) = abi.decode(callData[4:], (address, uint256, bytes));
            firstTargetContract = targetContract;
        } else {
            // Handle unknown function or error
            revert("Unknown function selector");
        }
    }
    
}
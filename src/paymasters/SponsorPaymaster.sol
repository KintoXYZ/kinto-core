// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

/* solhint-disable reason-string */

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '../interfaces/ISponsorPaymaster.sol';

import '@aa/core/BasePaymaster.sol';
import 'forge-std/console2.sol';

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

    mapping(address => uint256) public balances;
    mapping(address => uint256) public contractSpent; // keeps track of total gas consumption by contract
    mapping(address => uint256) public unlockBlock;

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
        unlockTokenDeposit();
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
        withdrawTo(payable(target), amount);
        balances[msg.sender] -= amount;
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
        // Get the contract deployed address from the first 20 bytes of the paymasterAndData
        address targetAccount =  address(bytes20(userOp.callData[16:]));
        uint256 gasPriceUserOp = userOp.gasPrice();
        require(unlockBlock[targetAccount] == 0, 'DepositPaymaster: deposit not locked');
        require(balances[targetAccount] >= maxCost, 'DepositPaymaster: deposit too low');
        return (abi.encode(targetAccount, gasPriceUserOp), 0);
    }

    /**
     * perform the post-operation to charge the sender for the gas.
     * in normal mode, use transferFrom to withdraw enough tokens from the sender's balance.
     * in case the transferFrom fails, the _postOp reverts and the entryPoint will call it again,
     * this time in *postOpReverted* mode.
     * In this mode, we use the deposit to pay (which we validated to be large enough)
     */
    function _postOp(PostOpMode /* mode */, bytes calldata context, uint256 actualGasCost) internal override {
        (address account, uint256 gasPricePostOp) = abi.decode(context, (address, uint256));
        //use same conversion rate as used for validation.
        uint256 ethCost = (actualGasCost + COST_OF_POST * gasPricePostOp);
        balances[account] -= ethCost;
        contractSpent[account] += ethCost;
        balances[owner()] += ethCost;
    }
    
}
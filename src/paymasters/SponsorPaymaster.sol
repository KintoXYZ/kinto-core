// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@aa/core/BasePaymaster.sol";
import "@solady/utils/LibZip.sol";

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
    uint256 public constant MAX_COST_OF_PREVERIFICATION = 1_500_000;

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

    mapping(string => address) public kintoContracts; // mapping of Kinto contract names to addresses
    mapping(address => string) public kintoNames; // mapping of Kinto contract addresses to names

    // ========== Events ============

    event AppRegistrySet(address oldRegistry, address newRegistry);
    event UserOpMaxCostSet(uint256 oldUserOpMaxCost, uint256 newUserOpMaxCost);
    event KintoContractSet(string name, address target);

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
        if (!kintoID.isKYC(msg.sender) && msg.sender != owner()) revert SenderKYCRequired();
        if (account.code.length == 0 && !kintoID.isKYC(account)) revert AccountKYCRequired();

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
        if (balances[msg.sender] < amount || unlockBlock[msg.sender] == 0 || block.number <= unlockBlock[msg.sender]) {
            revert TokenDepositLocked();
        }
        if (target == address(0) || target.code.length > 0) revert InvalidTarget();
        balances[msg.sender] -= amount;
        entryPoint.withdrawTo(payable(target), amount);
    }

    /* ============ Inflate & Compress ============ */

    function inflate(bytes calldata compressed) external view returns (UserOperation memory op) {
        // decompress the data
        return this._inflate(LibZip.flzDecompress(compressed));
    }

    function _inflate(bytes calldata decompressed) public view returns (UserOperation memory op) {
        uint256 cursor = 0; // keep track of the current position in the decompressed data

        // extract flags
        uint8 flags = uint8(decompressed[cursor]);
        cursor += 1;

        // extract `sender`
        op.sender = address(uint160(bytes20(decompressed[cursor:cursor + 20])));
        cursor += 20;

        // extract `nonce`
        op.nonce = uint32(bytes4(decompressed[cursor:cursor + 4]));
        cursor += 4;

        // extract `initCode`
        uint32 initCodeLength = uint32(bytes4(decompressed[cursor:cursor + 4]));
        cursor += 4;
        op.initCode = _slice(decompressed, cursor, initCodeLength);
        cursor += initCodeLength;

        // Decode callData based on the selector (execute or executeBatch)
        bytes memory callData;
        if (flags & 0x01 == 0x01) {
            // if selector is `execute`, decode the callData as a single operation
            (cursor, callData) = _inflateExecuteCalldata(op.sender, flags, decompressed, cursor);
        } else {
            // if selector is `executeBatch`, decode the callData as a batch of operations
            (cursor, callData) = _inflateExecuteBatchCalldata(decompressed, cursor);
        }
        op.callData = callData;

        // extract gas parameters and other values using direct conversions
        op.callGasLimit = uint256(bytes32(decompressed[cursor:cursor + 32]));
        cursor += 32;

        op.verificationGasLimit = uint256(bytes32(decompressed[cursor:cursor + 32]));
        cursor += 32;

        op.preVerificationGas = uint32(bytes4(decompressed[cursor:cursor + 4]));
        cursor += 4;

        op.maxFeePerGas = uint48(bytes6(decompressed[cursor:cursor + 6]));
        cursor += 6;

        op.maxPriorityFeePerGas = uint48(bytes6(decompressed[cursor:cursor + 6]));
        cursor += 6;

        // Extract paymasterAndData if the flag is set
        if (flags & 0x02 == 0x02) {
            op.paymasterAndData = abi.encodePacked(kintoContracts["SP"]);
        }

        // Decode signature length and content
        uint32 signatureLength = uint32(bytes4(decompressed[cursor:cursor + 4]));
        cursor += 4;
        require(cursor + signatureLength <= decompressed.length, "Invalid signature length");
        op.signature = decompressed[cursor:cursor + signatureLength];

        return op;
    }

    function compress(UserOperation memory op) external view returns (bytes memory compressed) {
        // initialize a dynamic bytes array for the pre-compressed data
        bytes memory buffer = new bytes(1024); // arbitrary size of 1024 bytes (resized later)
        uint256 cursor = 0;

        // decode `callData` (selector, target, value, bytesOp)

        // decode selector and prepare callData
        bytes4 selector = bytes4(_slice(op.callData, 0, 4));
        bytes memory callData = _slice(op.callData, 4, op.callData.length - 4);

        // set flags based on conditions into buffer
        buffer[cursor] = bytes1(_flags(selector, op, callData));
        cursor += 1;

        // encode `sender`, `nonce` and `initCode`
        cursor = _encodeAddress(op.sender, buffer, cursor);
        cursor = _encodeUint32(op.nonce, buffer, cursor); // we assume `nonce` can't fits in 32 bits
        cursor = _encodeBytes(op.initCode, buffer, cursor);

        // encode `callData` depending on the selector
        if (selector == IKintoWallet.execute.selector) {
            // if selector is `execute`, encode the callData as a single operation
            (address target,, bytes memory bytesOp) = abi.decode(callData, (address, uint256, bytes));
            cursor = _encodeExecuteCalldata(op, target, bytesOp, buffer, cursor);
        } else {
            // if selector is `executeBatch`, encode the callData as a batch of operations
            (address[] memory targets,, bytes[] memory bytesOps) = abi.decode(callData, (address[], uint256[], bytes[]));
            cursor = _encodeExecuteBatchCalldata(targets, bytesOps, buffer, cursor);
        }

        // encode gas params: `callGasLimit`, `verificationGasLimit`, `preVerificationGas`, `maxFeePerGas`, `maxPriorityFeePerGas`
        cursor = _encodeUint256(op.callGasLimit, buffer, cursor);
        cursor = _encodeUint256(op.verificationGasLimit, buffer, cursor);
        cursor = _encodeUint32(op.preVerificationGas, buffer, cursor);
        cursor = _encodeUint48(op.maxFeePerGas, buffer, cursor);
        cursor = _encodeUint48(op.maxPriorityFeePerGas, buffer, cursor);

        // encode `paymasterAndData` (we assume always the same paymaster so we don't need to encode it)
        // cursor = _encodeBytes(op.paymasterAndData, buffer, cursor);

        // encode `signature` content
        cursor = _encodeBytes(op.signature, buffer, cursor);

        // trim buffer size to the actual data length
        compressed = new bytes(cursor);
        for (uint256 i = 0; i < cursor; i++) {
            compressed[i] = buffer[i];
        }

        return LibZip.flzCompress(compressed);
    }

    /* ============ Simple compress/inflate ============ */

    function inflateSimple(bytes calldata compressed) external pure returns (UserOperation memory op) {
        op = abi.decode(LibZip.flzDecompress(compressed), (UserOperation));
    }

    function compressSimple(UserOperation memory op) external pure returns (bytes memory compressed) {
        compressed = LibZip.flzCompress(abi.encode(op));
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

    function setKintoContract(string memory name, address target) external onlyOwner {
        kintoContracts[name] = target;
        kintoNames[target] = name;
        // emit event
        emit KintoContractSet(name, target);
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

        address sponsor = appRegistry.getSponsor(_decodeCallData(userOp.callData));
        if (unlockBlock[sponsor] != 0) revert DepositNotLocked();
        if (balances[sponsor] < ethMaxCost) revert DepositTooLow();
        return (abi.encode(sponsor, userOp.sender, userOp.maxFeePerGas, userOp.maxPriorityFeePerGas), 0);
    }

    /**
     * @notice performs the post-operation to charge the account contract for the gas.
     */
    function _postOp(PostOpMode, /* mode */ bytes calldata context, uint256 actualGasCost) internal override {
        (address account, address walletAccount, uint256 maxFeePerGas, uint256 maxPriorityFeePerGas) =
            abi.decode(context, (address, address, uint256, uint256));

        // calculate actual gas limits using the owner because a person can have many wallets
        address userAccount = IKintoWallet(walletAccount).owners(0);
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

    /* ============ Inflate Helpers ============ */

    /// @notice extracts `calldata` (selector, target, value, bytesOp)
    /// @dev skips `value` since we assume it's always 0
    function _inflateExecuteCalldata(address sender, uint8 flags, bytes memory data, uint256 cursor)
        internal
        view
        returns (uint256 newCursor, bytes memory callData)
    {
        // 1. extract target
        address target;

        // if fourth flag is set, it means target is a Kinto contract
        if (flags & 0x08 == 0x08) {
            uint8 nameLength = uint8(data[cursor]);
            cursor += 1;
            string memory name = string(_slice(data, cursor, nameLength));
            cursor += nameLength;

            // get contract address from mapping
            target = kintoContracts[name];
        } else {
            // if third flag is set, it means target == sender
            if (flags & 0x04 == 0x04) {
                target = sender;
            } else {
                // if target is not a Kinto contract, just extract target address
                target = _bytesToAddress(data, cursor);
                cursor += 20;
            }
        }

        // 2. extract bytesOp
        uint256 bytesOpLength = _bytesToUint32(data, cursor);
        cursor += 4;
        bytes memory bytesOp = _slice(data, cursor, bytesOpLength);
        cursor += bytesOpLength;

        // 3. build `callData`
        callData = abi.encodeCall(IKintoWallet.execute, (target, 0, bytesOp));

        newCursor = cursor;
    }

    function _inflateExecuteBatchCalldata(bytes memory data, uint256 cursor)
        internal
        pure
        returns (uint256 newCursor, bytes memory callData)
    {
        // extract number of operations in the batch
        uint8 numOps = uint8(data[cursor]);
        cursor += 1;

        address[] memory targets = new address[](numOps);
        uint256[] memory values = new uint256[](numOps);
        bytes[] memory bytesOps = new bytes[](numOps);

        // extract targets, values, and bytesOps
        for (uint8 i = 0; i < numOps; i++) {
            // extract target
            targets[i] = _bytesToAddress(data, cursor);
            cursor += 20;

            // extract value (we assume this is always 0 for now)
            values[i] = 0;

            // extract bytesOp
            uint256 bytesOpLength = _bytesToUint32(data, cursor);
            cursor += 4;
            bytesOps[i] = _slice(data, cursor, bytesOpLength);
            cursor += bytesOpLength;
        }

        //build `callData`
        callData = abi.encodeCall(IKintoWallet.executeBatch, (targets, values, bytesOps));

        newCursor = cursor;
    }

    /* ============ Compress Helpers ============ */

    function _flags(bytes4 selector, UserOperation memory op, bytes memory callData)
        internal
        view
        returns (uint8 flags)
    {
        // encode boolean flags into the first byte of the buffer
        flags |= (selector == IKintoWallet.execute.selector) ? 0x01 : 0; // first bit for selector
        flags |= op.paymasterAndData.length > 0 ? 0x02 : 0; // second bit for paymasterAndData

        if (selector == IKintoWallet.execute.selector) {
            // we skip value since we assume it's always 0
            (address target,,) = abi.decode(callData, (address, uint256, bytes));
            flags |= op.sender == target ? 0x04 : 0; // third bit for sender == target
            flags |= _isKintoContract(target) ? 0x08 : 0; // fourth bit for Kinto contract
        } else {
            (address[] memory targets,,) = abi.decode(callData, (address[], uint256[], bytes[]));
            // num ops
            uint256 numOps = targets.length;
            flags |= uint8(numOps << 1); // 2nd to 7th bits for number of operations in the batch
        }
    }

    function _encodeExecuteCalldata(
        UserOperation memory op,
        address target,
        bytes memory bytesOp,
        bytes memory buffer,
        uint256 index
    ) internal view returns (uint256 newIndex) {
        // 1. encode `target`

        // if sender and target are different, encode the target address
        // otherwise, we don't need to encode the target at all
        if (op.sender != target) {
            // if target is a Kinto contract, encode the Kinto contract name
            if (_isKintoContract(target)) {
                string memory name = kintoNames[target];
                bytes memory nameBytes = bytes(name);
                buffer[index] = bytes1(uint8(nameBytes.length));
                index += 1;
                for (uint256 i = 0; i < nameBytes.length; i++) {
                    buffer[index + i] = nameBytes[i];
                }
                index += nameBytes.length;
            } else {
                // if target is not a Kinto contract, encode the target address
                index = _encodeAddress(target, buffer, index);
            }
        }

        // 2. encode `value` (always 0 for now)
        // index = _encodeUint256(value, buffer, index);

        // 3. encode `bytesOp` length and content
        newIndex = _encodeBytes(bytesOp, buffer, index);
    }

    function _encodeExecuteBatchCalldata(
        address[] memory targets,
        bytes[] memory bytesOps,
        bytes memory buffer,
        uint256 index
    ) internal pure returns (uint256 newIndex) {
        // encode number of operations in the batch
        buffer[index] = bytes1(uint8(targets.length));
        index += 1;

        // encode targets (as addresses, potentially we can improve this)
        for (uint8 i = 0; i < uint8(targets.length); i++) {
            index = _encodeAddress(targets[i], buffer, index);

            // encode bytesOps content
            index = _encodeBytes(bytesOps[i], buffer, index);
        }

        newIndex = index;
    }

    /* =============== Internal methods ============= */

    function _checkLimits(address sender, address targetAccount, uint256 ethMaxCost) internal view {
        // global rate limit check
        ISponsorPaymaster.RateLimitData memory globalData = globalRateLimit[sender];

        // Kinto rate limit check
        if (
            block.timestamp < globalData.lastOperationTime + RATE_LIMIT_PERIOD
                && globalData.operationCount > RATE_LIMIT_THRESHOLD_TOTAL
        ) revert KintoRateLimitExceeded();

        // app rate limit check
        uint256[4] memory appLimits = appRegistry.getContractLimits(targetAccount);
        ISponsorPaymaster.RateLimitData memory appData = rateLimit[sender][targetAccount];

        if (block.timestamp < appData.lastOperationTime + appLimits[0] && appData.operationCount > appLimits[1]) {
            revert AppRateLimitExceeded();
        }

        // app gas limit check
        ISponsorPaymaster.RateLimitData memory gasData = costLimit[sender][targetAccount];
        if (
            block.timestamp < gasData.lastOperationTime + appLimits[2]
                && (gasData.ethCostCount + ethMaxCost) > appLimits[3]
        ) revert KintoGasAppLimitExceeded();
    }

    function _isKintoContract(address target) internal view returns (bool) {
        if (keccak256(abi.encodePacked(kintoNames[target])) != keccak256("")) {
            return true;
        }
        return false;
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

    /// @dev slice bytes arrays
    function _slice(bytes memory data, uint256 start, uint256 length) internal pure returns (bytes memory) {
        bytes memory part = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            part[i] = data[i + start];
        }
        return part;
    }

    function _bytesToAddress(bytes memory data, uint256 start) private pure returns (address addr) {
        require(data.length >= start + 20, "Data too short");
        assembly {
            addr := mload(add(add(data, 20), start))
        }
    }

    function _bytesToUint32(bytes memory _bytes, uint256 start) internal pure returns (uint32 value) {
        require(_bytes.length >= start + 4, "Data too short");
        assembly {
            value := mload(add(add(_bytes, 4), start))
        }
    }

    function _encodeUint32(uint256 value, bytes memory buffer, uint256 index)
        internal
        pure
        returns (uint256 newIndex)
    {
        for (uint256 i = 0; i < 4; i++) {
            buffer[index + i] = bytes1(uint8(value >> (8 * (3 - i))));
        }
        return index + 4; // increase index by 4 bytes
    }

    function _encodeUint48(uint256 value, bytes memory buffer, uint256 index)
        internal
        pure
        returns (uint256 newIndex)
    {
        for (uint256 i = 0; i < 6; i++) {
            buffer[index + i] = bytes1(uint8(value >> (8 * (5 - i))));
        }
        return index + 6; // increase index by 6 bytes
    }

    function _encodeUint256(uint256 value, bytes memory buffer, uint256 index)
        internal
        pure
        returns (uint256 newIndex)
    {
        for (uint256 i = 0; i < 32; i++) {
            buffer[index + i] = bytes1(uint8(value >> (8 * (31 - i))));
        }
        return index + 32; // increase index by 32 bytes
    }

    function _encodeBytes(bytes memory data, bytes memory buffer, uint256 index)
        internal
        pure
        returns (uint256 newIndex)
    {
        // encode length of `data` (we assume uint32 is more than enough for the length)
        newIndex = _encodeUint32(data.length, buffer, index);

        // encode contents of `data`
        for (uint256 i = 0; i < data.length; i++) {
            buffer[newIndex + i] = data[i];
        }

        return newIndex + data.length; // increase index by the length of `data`
    }

    function _encodeAddress(address addr, bytes memory buffer, uint256 index)
        internal
        pure
        returns (uint256 newIndex)
    {
        bytes20 addrBytes = bytes20(addr);
        for (uint256 i = 0; i < 20; i++) {
            buffer[index + i] = addrBytes[i];
        }
        return index + 20;
    }
}

contract SponsorPaymasterV9 is SponsorPaymaster {
    constructor(IEntryPoint __entryPoint) SponsorPaymaster(__entryPoint) {}
}

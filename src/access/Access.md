# Access Protocol

## AccessRegistry
A registry contract that manages access points and workflow permissions in the protocol.

### Overview
The AccessRegistry serves as a central registry for access points, associating each user with a unique proxy and managing permissions for various workflows. It implements upgradeable patterns and uses an UpgradeableBeacon for creating proxies.

### Governance & Access Control
- Contract upgrades and workflow permissions are controlled by OpenZeppelin's AccessManager
- AccessManager is owned by a multisig wallet
- All sensitive operations (upgrades, workflow allowance changes) are subject to timelock delays
- Changes to workflows or implementations cannot take effect until the timelock period has passed
- The timelock provides users with a window to exit positions if they disagree with proposed changes

### Key Features
- Manages lifecycle of access points
- Controls workflow permissions through timelocked operations
- Upgradeable implementation using UUPS pattern
- Creates deterministic access point addresses using CREATE2
- Governance-controlled upgrades and workflow management

### Main Functions
- `initialize()`: Initializes the contract with initial owner and version
- `upgradeAll(IAccessPoint newImpl)`: Upgrades all access points to a new implementation (timelocked)
- `deployFor(address user)`: Deploys a new access point for a user
- `allowWorkflow(address workflow)`: Enables a workflow contract (timelocked)
- `disallowWorkflow(address workflow)`: Disables a workflow contract (timelocked)

## AccessPoint
A smart contract account that acts as a proxy for user interactions with the Kinto protocol.

### Overview
AccessPoint implements the EIP-4337 account abstraction standard and serves as an intermediary for users to interact with protocol workflows. It validates signatures and manages execution permissions.

### Key Features
- EIP-4337 compatible account abstraction
- Delegated execution of workflows
- Signature validation
- Access control via owner and EntryPoint

### Main Functions
- `execute(address target, bytes calldata data)`: Executes a workflow call
- `executeBatch(address[] calldata target, bytes[] calldata data)`: Executes multiple workflow calls
- `initialize(address owner_)`: Sets the initial owner of the access point

## AaveBorrowWorkflow
A workflow contract for borrowing assets from Aave markets.

### Overview
Enables users to borrow assets from Aave markets and optionally bridge them to another chain.

### Key Features
- Variable rate borrowing from Aave
- Integration with bridging functionality
- Direct interaction with Aave's lending pool

### Main Functions
- `borrow(address asset, uint256 amount)`: Borrows an asset from Aave
- `borrowAndBridge(address asset, uint256 amount, address kintoWallet, IBridger.BridgeData)`: Borrows and bridges assets

## AaveLendWorkflow
A workflow contract for lending (supplying) assets to Aave markets.

### Overview
Enables users to supply assets to Aave markets to earn yield.

### Key Features
- Supply assets to Aave markets
- Automatic approval management
- Direct interaction with Aave's lending pool

### Main Functions
- `lend(address assetIn, uint256 amountIn)`: Supplies assets to Aave markets

## AaveRepayWorkflow
A workflow contract for repaying borrowed assets to Aave markets.

### Overview
Enables users to repay their borrowed positions in Aave markets.

### Key Features
- Repay variable rate loans
- Support for full debt repayment
- Automatic approval management

### Main Functions
- `repay(address asset, uint256 amount)`: Repays borrowed assets to Aave

## AaveWithdrawWorkflow
A workflow contract for withdrawing supplied assets from Aave markets.

### Overview
Enables users to withdraw their supplied assets from Aave markets and optionally bridge them to another chain.

### Key Features
- Withdraw supplied assets from Aave
- Integration with bridging functionality
- Support for full position withdrawal

### Main Functions
- `withdraw(address asset, uint256 amount)`: Withdraws assets from Aave
- `withdrawAndBridge(address asset, uint256 amount, address kintoWallet, IBridger.BridgeData)`: Withdraws and bridges assets

## BridgeWorkflow
A workflow contract for bridging assets between chains.

### Overview
Facilitates the transfer of assets between different blockchain networks using bridge vaults.

### Key Features
- Cross-chain asset transfers
- Support for multiple bridge vaults
- Automatic approval management

### Main Functions
- `bridge(address asset, uint256 amount, address wallet, IBridger.BridgeData)`: Bridges assets to another chain

## SwapWorkflow
A workflow contract for token swaps using 0x Protocol.

### Overview
Enables token swaps through the 0x Protocol API with verifiable output amounts.

### Key Features
- Integration with 0x Protocol
- Automatic approval management
- Output amount verification
- Support for RFQ liquidity

### Main Functions
- `fillQuote(IERC20 tokenIn, uint256 amountIn, IERC20 tokenOut, bytes swapCallData)`: Executes a token swap

### Events
- `SwapExecuted(address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut)`: Emitted after successful swaps

### Security Considerations
1. All workflows require approval from the AccessRegistry
2. Operations can only be executed through validated AccessPoints
3. Most workflows implement automatic approval management
4. All external interactions are conducted through well-audited protocols (Aave, 0x)
5. Bridging operations verify vault validity before execution
6. Contract upgrades and workflow modifications are subject to timelock delays
7. Critical functions are protected by AccessManager and multisig controls
8. Users have time to exit positions during timelock period

### Governance Process
1. **Proposal**: Multisig proposes changes to workflows or implementations
2. **Timelock**: Changes enter mandatory waiting period
3. **User Choice**: Users can choose to exit during timelock if they disagree
4. **Execution**: Changes can be executed only after timelock expires
5. **Emergency**: Certain emergency functions may have shorter delays for security purposes

### Integration Guidelines
1. All interactions should occur through an AccessPoint
2. Workflow addresses must be whitelisted in AccessRegistry
3. Bridge operations require valid BridgeData structures
4. Swap operations require valid 0x API quotes
5. Aave operations should account for protocol limits and constraints
6. Integrators should monitor governance proposals for potential changes
7. Systems should handle potential workflow allowance changes gracefully

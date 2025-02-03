# SealedBidTokenSale Technical Specification

Below is the **technical specification** for a Solidity **sealed‐bid** token sale contract.

---

## 1. **Contract Overview**

- **Name**: `SealedBidTokenSale`  
- **Purpose**: Accept USDC deposits for a token sale, enforce timing and minimum cap requirements, enable refunds if the sale is unsuccessful, and distribute tokens and USDC allocations via a Merkle proof if successful.
- **Inheritance**: `Ownable`, `ReentrancyGuard`

---

## 2. **Key Roles**

- **Owner**:  
  - Inherits from OpenZeppelin `Ownable`.  
  - Sets crucial parameters during contract deployment.  
  - Controls sale finalization, Merkle root setting, and proceeds withdrawal.

- **Participants**:  
  - Deposit USDC during the sale window.  
  - Withdraw their deposit if the sale fails.  
  - Claim tokens and USDC allocations after sale success using a Merkle proof.

- **Treasury**:  
  - Immutable address specified at deployment.  
  - Receives USDC proceeds upon successful sale completion.

---

## 3. **Immutable Parameters**

1. **`saleToken`** (`IERC20`)  
   - Token being sold through the contract.
   - Set at construction.

2. **`USDC`** (`IERC20`)  
   - USDC token contract reference for deposits.
   - Set at construction.

3. **`treasury`** (`address`)  
   - Fixed address that receives proceeds.
   - Set at construction.

4. **`startTime`** (`uint256`)  
   - Sale start timestamp.
   - Set at construction.

5. **`minimumCap`** (`uint256`)  
   - Minimum USDC required for success.
   - Set at construction.

---

## 4. **State Variables**

1. **`saleEnded`** (`bool`)  
   - Indicates if owner has ended the sale.

2. **`capReached`** (`bool`)  
   - Set to `true` if `totalDeposited >= minimumCap` when sale ends.

3. **`totalDeposited`** (`uint256`)  
   - Sum of all USDC deposits.

4. **`merkleRoot`** (`bytes32`)  
   - Root hash for token and USDC allocation proofs.

5. **`deposits`** (`mapping(address => uint256)`)  
   - Tracks each user's USDC deposit amount.

6. **`hasClaimed`** (`mapping(address => bool)`)  
   - Records whether an address has claimed their allocation.

---

## 5. **Core Functions**

### 5.1 **`deposit(uint256 amount)`**
- **Purpose**: Accepts USDC deposits from participants.  
- **Constraints**:  
  1. Must be after `startTime`.
  2. Sale must not be ended.
  3. Amount must be non-zero.
- **Effects**:  
  - Updates `deposits[msg.sender]` and `totalDeposited`.
  - Transfers USDC from sender to contract.
  - Emits `Deposited` event.

### 5.2 **`withdraw()`**
- **Purpose**: Returns USDC to depositors if sale fails.  
- **Constraints**:  
  1. Sale must be ended.
  2. Cap must not be reached.
  3. Caller must have non-zero deposit.
- **Effects**:  
  - Returns user's entire USDC deposit.
  - Zeroes their deposit balance.
  - Emits `Withdrawn` event.

### 5.3 **`endSale()`** (Owner-only)
- **Purpose**: Finalizes sale and determines success.  
- **Constraints**:  
  1. Only callable by owner.
  2. Sale must not already be ended.
- **Effects**:  
  - Sets `saleEnded = true`.
  - Sets `capReached` based on minimum cap check.
  - Emits `SaleEnded` event.

### 5.4 **`claimTokens(uint256 saleTokenAllocation, uint256 usdcAllocation, bytes32[] calldata proof, address user)`**
- **Purpose**: Processes token and USDC claims using Merkle proofs.  
- **Constraints**:  
  1. Sale must be ended and successful.
  2. Merkle root must be set.
  3. User must not have claimed.
  4. Valid Merkle proof required.
- **Effects**:  
  - Marks user as claimed.
  - Transfers allocated sale tokens.
  - Returns allocated USDC.
  - Emits `Claimed` event.

### 5.5 **`setMerkleRoot(bytes32 newRoot)`** (Owner-only)
- **Purpose**: Sets allocation Merkle root.
- **Constraints**:  
  1. Sale must be ended and successful.
  2. Only callable by owner.
- **Effects**:  
  - Sets `merkleRoot`.
  - Emits `MerkleRootSet` event.

### 5.6 **`withdrawProceeds()`** (Owner-only)
- **Purpose**: Sends USDC to treasury.
- **Constraints**:  
  1. Sale must be ended and successful.
  2. Only callable by owner.
- **Effects**:  
  - Transfers all USDC to treasury address.

---

## 6. **Custom Errors**

1. **Parameter Validation**:
   - `InvalidSaleTokenAddress`
   - `InvalidTreasuryAddress`
   - `ZeroDeposit`

2. **State Checks**:
   - `SaleNotStarted`
   - `SaleAlreadyEnded`
   - `SaleNotEnded`
   - `CapNotReached`
   - `SaleWasSuccessful`

3. **Claim Validation**:
   - `NothingToWithdraw`
   - `AlreadyClaimed`
   - `InvalidProof`
   - `MerkleRootNotSet`


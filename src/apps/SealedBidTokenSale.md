# Updated Technical Specification

Below is the revised **technical specification** for a Solidity **sealed‐bid, multi‐unit uniform‐price** token sale contract. The specification reflects the latest changes:

1. **Use of OpenZeppelin’s `Ownable`** for ownership logic.  
2. **Withdrawal of proceeds** goes to a **predetermined treasury address**.  

All other core features—time‐limited deposits in USDC, minimum/maximum cap checks, finalization logic, off‐chain price discovery, Merkle‐based token claims, and refunds if the sale fails—remain consistent with the previous design.

---

## 1. **Contract Overview**

- **Name**: `SealedBidTokenSale`  
- **Purpose**: Accept USDC deposits for an off‐chain price discovery token sale, enforce timing and caps, enable refunds if the sale is unsuccessful, and distribute tokens (via a Merkle proof) if successful.

---

## 2. **Key Roles**

- **Owner**:  
  - Inherits from OpenZeppelin `Ownable`.  
  - The owner sets crucial parameters during contract deployment.  
  - The owner finalizes the sale, sets the Merkle root, and withdraws proceeds to the treasury address.

- **Participants**:  
  - Deposit USDC during the sale window.  
  - Withdraw their deposit if the sale fails.  
  - Claim tokens after the sale succeeds, using a Merkle proof.

- **Treasury**:  
  - A predetermined address specified at contract deployment.  
  - Receives the USDC proceeds if the sale succeeds.

---

## 3. **Immutable & Configurable Parameters**

1. **`Ownable`**  
   - The contract is governed by an owner (`owner()`) managed by OpenZeppelin’s `Ownable`.

2. **`treasury`** (`address`)  
   - Set at construction.  
   - **Immutable**; where funds are sent on success.

3. **`usdcToken`** (`IERC20`)  
   - The address of the USDC contract.  
   - Used for `transferFrom` and `transfer` calls.

4. **`startTime`** and **`endTime`** (`uint256`)  
   - The sale window during which deposits are accepted.

5. **`minimumCap`** (`uint256`)  
   - The minimum total USDC deposit threshold required for the sale to succeed.

6. **`maximumCap`** (`uint256`)  
   - The maximum total USDC deposit allowed; can be `0` if no maximum limit is needed.

---

## 4. **State Variables**

1. **`finalized`** (`bool`)  
   - Indicates if the sale has been finalized.  
   - Once set, the contract’s deposit logic is locked.

2. **`successful`** (`bool`)  
   - `true` if `totalDeposited >= minimumCap` upon finalization.  
   - Determines whether users can claim tokens or must withdraw refunds.

3. **`totalDeposited`** (`uint256`)  
   - Running total of all USDC deposits received.

4. **`deposits`** (`mapping(address => uint256)`)  
   - Tracks each participant’s cumulative deposit.

5. **`merkleRoot`** (`bytes32`)  
   - Root hash of an off‐chain Merkle tree that encodes final token allocations.

6. **`hasClaimed`** (`mapping(address => bool)`)  
   - Tracks whether a participant has already claimed tokens.

---

## 5. **Core Functions**

### 5.1 **`deposit(uint256 amount)`**
- **Purpose**: Allows participants to deposit USDC into the sale, multiple times if desired.  
- **Constraints**:  
  1. Must be called after `startTime` and before `endTime`.  
  2. Sale must not be `finalized`.  
  3. The `amount` must be non-zero.  
  4. If `maximumCap > 0`, `totalDeposited + amount <= maximumCap`.  
  5. Transfers USDC using `transferFrom(msg.sender, address(this), amount)`.  
- **Effects**:  
  - Increments `deposits[msg.sender]` and `totalDeposited`.  
  - Emits a `Deposit` event.

### 5.2 **`withdraw()`**
- **Purpose**: Allows participants to **refund** their USDC deposits if the sale fails.  
- **Constraints**:  
  1. Can only be called after `finalized`.  
  2. Only possible if `successful == false`.  
  3. Caller’s `deposits[msg.sender]` must be > 0.  
- **Effects**:  
  - Refunds the user’s entire deposit via `transfer`.  
  - Sets `deposits[msg.sender] = 0` to prevent re‐entrancy.  
  - Emits a `Withdraw` event.

### 5.3 **`finalize()`** (Owner‐only)
- **Purpose**: Ends the deposit phase, locks in whether the sale is successful, and stops further deposits.  
- **Constraints**:  
  1. Can only be called by the **owner**.  
  2. Must not be already `finalized`.  
  3. Typically requires current time >= `endTime` **or** `totalDeposited == maximumCap` (if the cap is exhausted early).  
- **Effects**:  
  - Sets `finalized = true`.  
  - Sets `successful = (totalDeposited >= minimumCap)`.  
  - Emits a `Finalized` event with the final outcome.

### 5.4 **`setMerkleRoot(bytes32 _merkleRoot)`** (Owner‐only)
- **Purpose**: Records the final allocations in a **Merkle root** for off‐chain computed distribution.  
- **Constraints**:  
  1. Must be called by the **owner**.  
  2. The sale must be `finalized` and `successful`.  
- **Effects**:  
  - Updates `merkleRoot` to `_merkleRoot`.  
  - Emits a `MerkleRootSet` event.

### 5.5 **`claimTokens(uint256 allocation, bytes32[] calldata proof)`**
- **Purpose**: Lets each participant claim their allocated tokens (as computed off‐chain), verified by a **Merkle proof**.  
- **Constraints**:  
  1. The sale must be `finalized` and `successful`.  
  2. A valid `merkleRoot` must be set.  
  3. `hasClaimed[msg.sender] == false` (no double‐claim).  
  4. The `(address, allocation)` leaf must be verified against `merkleRoot` using `MerkleProof.verify`.  
- **Effects**:  
  - Marks `hasClaimed[msg.sender] = true`.  
  - **Transfers** (or **mints**) `allocation` tokens to the caller.  
  - Emits a `Claim` event.

### 5.6 **`withdrawProceeds()`** (Owner‐only)
- **Purpose**: Transfers **all** USDC proceeds to the **predetermined `treasury`** address if the sale is successful.  
- **Constraints**:  
  1. Must be called by the **owner**.  
  2. The sale must be `finalized` and `successful`.  
- **Effects**:  
  - Transfers the entire USDC balance from the contract to `treasury`.

---

## 6. **Life Cycle**

1. **Deployment**  
   - Deployed with constructor parameters, including `treasury`, `startTime`, `endTime`, `minimumCap`, `maximumCap`.  
   - The contract references the USDC address for deposits.

2. **Deposit Phase**  
   - Participants call `deposit(amount)` any number of times from `startTime` to `endTime` (unless `maximumCap` is reached).  
   - `totalDeposited` is aggregated.

3. **Finalization**  
   - After `endTime` (or upon reaching `maximumCap`), the owner calls `finalize()`.  
   - The contract determines `successful` based on `minimumCap`.

4. **Outcomes**  
   - **Unsuccessful**: If `totalDeposited < minimumCap`, participants can call `withdraw()` to get refunds.  
   - **Successful**:  
     - The owner sets a `merkleRoot` to define each user’s final token allocation.  
     - Participants use `claimTokens(allocation, proof)` to claim tokens.  
     - The owner can call `withdrawProceeds()` to send USDC to the `treasury`.

---

## 7. **Implementation Considerations**

1. **Token Distribution Mechanism**  
   - The contract must hold or be able to mint the tokens for `claimTokens()`.  
   - This might involve transferring tokens in advance or using a mint function in an external token contract.

2. **Security**  
   - Use **OpenZeppelin** libraries (`Ownable`, `ReentrancyGuard`, `MerkleProof`) for best practices.  
   - Validate deposit calls to prevent deposits outside the allowed window.  
   - Carefully handle refunds (set user deposit to 0 before transferring USDC back).

3. **Edge Cases**  
   - If `maximumCap == 0`, only time gating applies.  
   - If participants deposit after `maximumCap` is reached, the contract must revert.  
   - The owner might finalize **early** if `totalDeposited == maximumCap` before `endTime`.  
   - If `startTime` equals `endTime` or if `_endTime <= _startTime`, the constructor should revert.

4. **No Immediate Secondary Trading**  
   - The specification assumes tokens are **not** tradable until after the sale.  
   - Participants may hold or wait to claim tokens; however, that is outside the core on‐chain deposit/refund logic.

5. **Custom Errors**  
   - Reverts use 0.8‐style **custom errors** for gas efficiency (e.g., `error SaleNotStarted();`, `error SaleEnded();`, etc.).  

---

## 8. **Final Takeaway**

This specification establishes a **time‐bound, USDC‐based deposit system** with:

- A **minimum funding threshold** (`minimumCap`) for success.  
- An **optional maximum** (`maximumCap`).  
- **Finalization** by the owner.  
- **Refunds** if not successful.  
- **Merkle‐based claims** if successful.  
- **Proceeds** withdrawn by the owner to a **fixed `treasury` address**.  

All **off‐chain** bid details and final allocation logic remain external; the contract only enforces **deposits**, **caps**, **timing**, and **fund distribution**, while using a **Merkle tree** for post‐sale token allocation.

const fs = require('fs');
const path = require('path');

const USDC_SCALE = 1_000_000n;                 // 1 USDC = 1e6
const TOKEN_SCALE = 1_000_000_000_000_000_000n; // 1 TOKEN = 1e18

/**
 * Runs a uniform-price auction aiming to raise a specified total USDC amount.
 *
 * @param {Object[]} bids
 * @param {string}   bids[].address     - Ethereum address.
 * @param {bigint}   bids[].usdcAmount  - USDC in 1e6 units.
 * @param {bigint}   bids[].maxPrice    - Max price in USDC’s 1e6 format (6 decimals).
 * @param {bigint}   bids[].priority    - Priority for tie-breaks.
 * @param {bigint}   totalUSDCRequired  - Total USDC (in 1e6) to be raised by the auction.
 *
 * @returns {{
 *   finalPrice: bigint,  // Price per token in 1e6 USDC units (6 decimals)
 *   allocations: {
 *     [address: string]: {
 *       tokens: bigint,      // Tokens allocated (18 decimals)
 *       usedUSDC: bigint,    // USDC actually used (6 decimals)
 *       refundedUSDC: bigint // USDC refunded (6 decimals)
 *     }
 *   }
 * }}
 */
function runAuction(bids, totalUSDCRequired) {
  // 1) Sort bids by maxPrice (desc), then priority (desc)
  bids.sort((a, b) => {
    if (b.maxPrice === a.maxPrice) {
      return Number(b.priority - a.priority);
    }
    return Number(b.maxPrice - a.maxPrice);
  });

  // 2) Find the clearing price by accumulating USDC until totalUSDCRequired is reached
  let cumulativeUSDC = 0n;
  let finalPrice = 0n;

  // We'll track the index of the "clearing bidder" and how much USDC we used from them
  let clearingIndex = -1;
  let partialUsedFromClearingBidder = 0n;

  for (let i = 0; i < bids.length; i++) {
    const bid = bids[i];

    // If adding the full bid.usdcAmount crosses the required threshold
    if (cumulativeUSDC + bid.usdcAmount >= totalUSDCRequired) {
      finalPrice = bid.maxPrice;
      partialUsedFromClearingBidder = totalUSDCRequired - cumulativeUSDC;  // can be full or partial
      clearingIndex = i;
      break;
    } else {
      cumulativeUSDC += bid.usdcAmount;
    }
  }

  // 3) If finalPrice is 0 => not enough demand => everyone refunded
  if (finalPrice === 0n) {
    const allocations = {};
    for (const bid of bids) {
      allocations[bid.address] = {
        tokens: 0n,
        usedUSDC: 0n,
        refundedUSDC: bid.usdcAmount
      };
    }
    return { finalPrice, allocations };
  }

  // 4) We know the finalPrice and exactly how much we used from the clearing bidder
  const allocations = {};
  let usdcUsedSoFar = 0n;

  for (let i = 0; i < bids.length; i++) {
    const bid = bids[i];

    // If we've passed the clearing index, or the bidder's maxPrice < finalPrice => no allocation
    if (i > clearingIndex || bid.maxPrice < finalPrice) {
      allocations[bid.address] = {
        tokens: 0n,
        usedUSDC: 0n,
        refundedUSDC: bid.usdcAmount
      };
      continue;
    }

    // If this is before the clearing bidder => full usage
    if (i < clearingIndex) {
      const usedUSDC = bid.usdcAmount;
      const tokens = (usedUSDC * TOKEN_SCALE) / finalPrice;

      let refundedUSDC = bid.usdcAmount - usedUSDC;
      if (refundedUSDC < 2n) {
        refundedUSDC = 0n;
      }

      allocations[bid.address] = {
        tokens,
        usedUSDC,
        refundedUSDC
      };
      usdcUsedSoFar += usedUSDC;
    }
    // If this is exactly the clearing bidder => partial usage
    else if (i === clearingIndex) {
      const usedUSDC = partialUsedFromClearingBidder;
      const tokens = (usedUSDC * TOKEN_SCALE) / finalPrice;

      let refundedUSDC = bid.usdcAmount - usedUSDC;
      if (refundedUSDC < 2n) {
        refundedUSDC = 0n;
      }

      allocations[bid.address] = {
        tokens,
        usedUSDC,
        refundedUSDC
      };
      usdcUsedSoFar += usedUSDC;
    }
  }

  return { finalPrice, allocations };
}

/**
 * Verifies that the allocations are consistent with the bids and finalPrice:
 *  1. For each bidder, usedUSDC + refundedUSDC == bid.usdcAmount
 *  2. If finalPrice > 0, tokens == (usedUSDC * 1e18) / finalPrice
 *  3. Sum(usedUSDC) + Sum(refundedUSDC) across all bidders == sum of all bids' usdcAmount
 *
 * Throws an Error if any check fails, otherwise logs success.
 *
 * @param {Object[]} bids
 * @param {bigint}   bids[].usdcAmount
 * @param {string}   bids[].address
 * @param {bigint}   finalPrice
 * @param {Object}   allocations
 */
function verifyAllocations(bids, finalPrice, allocations) {
  let totalUsedUSDC = 0n;
  let totalRefundedUSDC = 0n;
  let totalTokens = 0n;
  let originalTotalUSDC = 0n;

  for (const bid of bids) {
    originalTotalUSDC += bid.usdcAmount;

    const { tokens = 0n, usedUSDC = 0n, refundedUSDC = 0n } =
      allocations[bid.address] || {};

    // Check that usedUSDC + refundedUSDC == original bid
    if (usedUSDC + refundedUSDC !== bid.usdcAmount) {
      throw new Error(
        `Allocation mismatch for ${bid.address}: usedUSDC + refundedUSDC != bid.usdcAmount`
      );
    }

    // Check token calculation if finalPrice > 0
    if (finalPrice > 0n) {
      const expectedTokens = (usedUSDC * TOKEN_SCALE) / finalPrice;
      if (tokens !== expectedTokens) {
        throw new Error(
          `Allocation mismatch for ${bid.address}: tokens (${tokens}) != expectedTokens (${expectedTokens})`
        );
      }
    } else {
      // If finalPrice is zero, tokens must be zero
      if (tokens !== 0n) {
        throw new Error(
          `Allocation mismatch for ${bid.address}: finalPrice=0 => tokens should be 0`
        );
      }
    }

    // Tally for global checks
    totalUsedUSDC += usedUSDC;
    totalRefundedUSDC += refundedUSDC;
    totalTokens += tokens;
  }

  // Check global USDC usage
  if (totalUsedUSDC + totalRefundedUSDC !== originalTotalUSDC) {
    throw new Error(
      `Global USDC mismatch: (used + refunded) = ${
        totalUsedUSDC + totalRefundedUSDC
      }, expected ${originalTotalUSDC}`
    );
  }

  console.log(`verifyAllocations:`);
  console.log(`  ✓ All per-bidder checks passed`);
  console.log(`  ✓ Global USDC usage matches`);
  console.log(`  Total tokens allocated: ${(totalTokens / TOKEN_SCALE).toString()}`);
  console.log(`  Total USDC used: ${(totalUsedUSDC / USDC_SCALE).toString()}`);
  console.log(`  Total USDC refunded: ${(totalRefundedUSDC / USDC_SCALE).toString()}`);
}

// ----------------------------------------------------------------------
//  Read bids from a file (address amount maxPrice priority)
// ----------------------------------------------------------------------
function readBidsFromFile(filePath) {
  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split(/\r?\n/);

  const bids = [];
  for (const line of lines) {
    if (!line.trim()) continue; // skip empty lines

    const [address, amountStr, maxPriceStr, priorityStr] = line
      .trim()
      .split(/\s+/);
    if (!address || !amountStr || !maxPriceStr || !priorityStr) {
      continue; // skip malformed lines
    }

    // Convert to BigInt (these are already in 1e6 for USDC or just integer priority)
    const usdcAmount = BigInt(amountStr);
    const maxPrice = BigInt(maxPriceStr);
    const priority = BigInt(priorityStr);

    bids.push({ address, usdcAmount, maxPrice, priority });
  }
  return bids;
}

// ----------------------------------------------------------------------
//  Write output file
// ----------------------------------------------------------------------
function writeOutputToFile(filePath, finalPrice, allocations) {
  let output = '';
  for (const address in allocations) {
    const { tokens, usedUSDC, refundedUSDC } = allocations[address];
    output += `${address} ${tokens.toString()} ${usedUSDC.toString()} ${refundedUSDC.toString()}\n`;
  }

  fs.writeFileSync(filePath, output, 'utf-8');
}

// ----------------------------------------------------------------------
//  Main
// ----------------------------------------------------------------------
function main() {
  const inputFilePath = path.join(__dirname, '../../script/data/auction/bids.txt');
  const outputFilePath = path.join(
    __dirname,
    '../../script/data/auction/allocations.txt'
  );

  // Read bids
  const bids = readBidsFromFile(inputFilePath);

  // Suppose we want to raise exactly 100,000 USDC.
  // 100,000 USDC => 100,000 * 1e6 = 100_000n * 1_000_000n
  const totalUSDCRequired = 1000_000n * USDC_SCALE; 

  // Run the auction
  const { finalPrice, allocations } = runAuction(bids, totalUSDCRequired);

  // Write the results to disk
  writeOutputToFile(outputFilePath, finalPrice, allocations);

  // Verify the allocations
  try {
    verifyAllocations(bids, finalPrice, allocations);
  } catch (err) {
    console.error(`Allocation verification failed: ${err.message}`);
    process.exit(1);
  }

  // Log
  const finalPriceFloat = Number(finalPrice) / Number(USDC_SCALE);
  console.log(
    `Auction complete. Final Price: ~$${finalPriceFloat.toFixed(
      2
    )} USDC/token.`
  );
  console.log(`Results written to ${outputFilePath}`);
}

// Execute if called directly (e.g. `node auction-bigint.js`)
if (require.main === module) {
  main();
}

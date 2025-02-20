const fs = require('fs');
const path = require('path');

function abs(x) {
    return x < 0n ? -x : x
  }

const USDC_SCALE = 1_000_000n;                  // 1 USDC = 1e6
const TOKEN_SCALE = 1_000_000_000_000_000_000n; // 1 TOKEN = 1e18

/**
 * Runs a uniform-price auction aiming to sell exactly `totalTokens`.
 *
 * @param {Object[]} bids
 * @param {string}   bids[].address     - Ethereum address.
 * @param {bigint}   bids[].usdcAmount  - USDC in 1e6 units (6 decimals).
 * @param {bigint}   bids[].maxPrice    - Max price in 1e6 USDC units (6 decimals).
 * @param {bigint}   bids[].priority    - Tie-break priority (desc).
 * @param {bigint}   totalTokens        - Total tokens (1e18) to be sold in the auction.
 *
 * @returns {{
 *   finalPrice: bigint,  // Clearing price in 1e6 USDC units (6 decimals)
 *   allocations: {
 *     [address: string]: {
 *       tokens: bigint,      // Tokens allocated in 1e18 units
 *       usedUSDC: bigint,    // USDC actually used in 1e6 units
 *       refundedUSDC: bigint // USDC refunded in 1e6 units
 *     }
 *   }
 * }}
 */
function runAuction(bids, totalTokens) {
  // 1) Collect all distinct maxPrices
  const allPrices = new Set();
  for (const b of bids) {
    allPrices.add(b.maxPrice);
  }
  // Sort them descending
  const distinctPricesDesc = Array.from(allPrices).sort((a, b) => Number(b - a));

  // 2) Find the "highest price p" such that the sum of tokens demanded
  //    by all bidders with maxPrice >= p is >= totalTokens.
  let finalPrice = 0n;
  
  for (const p of distinctPricesDesc) {
    let demanded = 0n;
    
    // Sum each bidder's demand at price p, if bidder.maxPrice >= p
    for (const bid of bids) {
      if (bid.maxPrice >= p) {
        // tokens = floor( (usdcAmount * 1e18) / p )
        // Make sure we don't do floating arithmetic
        const tokens = (bid.usdcAmount * TOKEN_SCALE) / p;
        demanded += tokens;
      }
    }
    
    // If total demanded >= totalTokens, p could be our clearing price
    // Keep the first (largest) p that satisfies this condition
    if (demanded >= totalTokens) {
      finalPrice = p;
      break;
    }
  }
  
  // 3) If finalPrice == 0, it means no price had enough demand => auction not fully subscribed
  //    => everyone gets 0 tokens & full refund
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

  // 4) We do a second pass to allocate exactly totalTokens at the finalPrice
  //    among all bidders whose maxPrice >= finalPrice.
  //    Sort them by priority desc (and if you want, tie-break on something else).
  const inTheMoney = bids
    .filter(b => b.maxPrice >= finalPrice)
    .sort((a, b) => Number(b.priority - a.priority));

  const allocations = {};
  let tokensLeft = totalTokens;

  // For bidders whose maxPrice < finalPrice, they get 0 allocation
  for (const bid of bids) {
    if (bid.maxPrice < finalPrice) {
      allocations[bid.address] = {
        tokens: 0n,
        usedUSDC: 0n,
        refundedUSDC: bid.usdcAmount
      };
    }
  }

  // Now allocate to those in the money
  for (const bid of inTheMoney) {
    // If no tokens remain, bidder gets nothing
    if (tokensLeft === 0n) {
      allocations[bid.address] = {
        tokens: 0n,
        usedUSDC: 0n,
        refundedUSDC: bid.usdcAmount
      };
      continue;
    }

    // Max tokens this bidder *could* buy at finalPrice:
    // demandedTokens = floor( (usdcAmount * 1e18) / finalPrice )
    let demandedTokens = (bid.usdcAmount * TOKEN_SCALE) / finalPrice;

    let usedUSDC;
    let refundedUSDC;
    // If the demand is more than what's left, they only get partial fill
    if (demandedTokens > tokensLeft) {
      demandedTokens = tokensLeft;
      // Calculate how much USDC that partial or full fill uses
      // usedUSDC = floor( demandedTokens * finalPrice / 1e18 )
      usedUSDC = (demandedTokens * finalPrice) / TOKEN_SCALE;
      refundedUSDC = bid.usdcAmount - usedUSDC;
    } else {
      // If we have tokens then just spend all
      usedUSDC = bid.usdcAmount;
      refundedUSDC = 0n;
    }


    allocations[bid.address] = {
      tokens: demandedTokens,
      usedUSDC,
      refundedUSDC: refundedUSDC < 0n ? 0n : refundedUSDC
    };

    // Decrease tokensLeft
    tokensLeft -= demandedTokens;
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
      if (abs(tokens - expectedTokens) > 2000) {
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
//  Read emissaries users from a file
// ----------------------------------------------------------------------
function readEmissariesFromFile(filePath, bids) {
  const content = fs.readFileSync(filePath, 'utf-8');
  const users = content.split(/\r?\n/);

  for (let index = 0; index < users.length; index++) {
    let user = users[index];
    for (const bid of bids) {
      // If Engen user then give priority
      if(user === bid.address) {
        const newPriority = users.length - index + 1e5;
        bid.priority = newPriority > bid.priority ? newPriority : bid.priority;
      }
    }
  }
  return bids;
}

// ----------------------------------------------------------------------
//  Read users from a file
// ----------------------------------------------------------------------
function readUsersFromFile(filePath, bids) {
  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split(/\r?\n/);

  const users = [];
  for (const line of lines) {
    if (!line.trim()) continue; // skip empty lines

    const [address, amountStr] = line
      .trim()
      .split(/\s+/);
    if (!address || !amountStr) {
      throw new Error('Corrupted file');
    }

    // Convert to BigInt
    const amount = BigInt(amountStr);

    users.push({ address, amount });
  }
  const sortedUsers = Array.from(users).sort((a, b) => Number(b.amount - a.amount));

  for (let index = 0; index < sortedUsers.length; index++) {
    let user = sortedUsers[index];
    for (const bid of bids) {
      // If Engen user then give priority
      if(user.address === bid.address) {
        const newPriority = sortedUsers.length - index;
        bid.priority = newPriority > bid.priority ? newPriority : bid.priority;
      }
    }
  }
  return bids;
}

// ----------------------------------------------------------------------
//  Read engen users from a file
// ----------------------------------------------------------------------
function readEngenFromFile(filePath, bids) {
  const content = fs.readFileSync(filePath, 'utf-8');
  const users = content.split(/\r?\n/);

  for (let index = 0; index < users.length; index++) {
    let user = users[index];
    for (const bid of bids) {
      // If Engen user then give priority
      if(user === bid.address) {
        bid.priority = users.length - index + 1e6;
      }
    }
  }
  return bids;
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
    const priority = Number(priorityStr);

    bids.push({ address, usdcAmount, maxPrice, priority });
  }
  return bids;
}

// ----------------------------------------------------------------------
//  Write bids file
// ----------------------------------------------------------------------
function writeBidsToFile(filePath, bids) {
  let output = '';
  for (const bid of bids) {
    const { address, usdcAmount, maxPrice, priority } = bid;
    output += `${address} ${usdcAmount.toString()} ${maxPrice.toString()} ${priority.toString()}\n`;
  }

  fs.writeFileSync(filePath, output, 'utf-8');
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
  const engenFilePath = path.join(__dirname, '../../script/data/auction/engen-holders.txt');
  const emissaryFilePath = path.join(__dirname, '../../script/data/auction/emissaries.txt');
  const usersFilePath = path.join(__dirname, '../../script/data/auction/users-k-balance.txt');
  const finalBidsFilePath = path.join(__dirname, '../../script/data/auction/final-bids.txt');

  // Read bids
  let bids = readBidsFromFile(inputFilePath);

  // Read Engen users and set priority for them
  bids = readEngenFromFile(engenFilePath, bids);

  // Read Emissary users and set priority for them
  bids = readEmissariesFromFile(emissaryFilePath, bids);

  // Read users and set priority for them
  bids = readUsersFromFile(usersFilePath, bids);

  // Write final bids for manual checks
  writeBidsToFile(finalBidsFilePath, bids);

  // Suppose we want to sell exactly 250,000 tokens
  const totalTokens = 250_000n * TOKEN_SCALE; 

  // Run the auction
  const { finalPrice, allocations } = runAuction(bids, totalTokens);

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

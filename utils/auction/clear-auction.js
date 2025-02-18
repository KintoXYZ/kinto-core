const fs = require('fs');
const path = require('path');

const USDC_SCALE = 1_000_000n;                // 1 USDC = 1e6

/**
 * Runs a uniform-price auction using BigInt with:
 *   - USDC in 6 decimals (1 USDC = 1e6)
 *   - Tokens in 18 decimals (1 TOKEN = 1e18)
 *
 * @param {Object[]} bids
 * @param {string}   bids[].address      - Ethereum address.
 * @param {bigint}   bids[].usdcAmount   - USDC in 1e6 units.
 * @param {bigint}   bids[].maxPrice     - Max price in USDC’s 1e6 format.
 * @param {bigint}   bids[].priority     - Priority for tie-breaks.
 * @param {bigint}   totalTokens         - Total tokens to sell in 1e18 units.
 *
 * @returns {{
 *   finalPrice: bigint,  // Price per token in 1e6 USDC units (6 decimals)
 *   allocations: {
 *     [address: string]: {
 *       tokens: bigint,      // Tokens allocated (18 decimals)
 *       usedUSDC: bigint,    // USDC used (6 decimals)
 *       refundedUSDC: bigint // USDC refunded (6 decimals)
 *     }
 *   }
 * }}
 */
function runAuction(bids, totalTokens) {
  // Constants for scaling
  const TOKEN_SCALE = 1_000_000_000_000_000_000n; // 1 TOKEN = 1e18

  // 1) Sort bids by maxPrice (desc), then priority (desc)
  bids.sort((a, b) => {
    if (b.maxPrice === a.maxPrice) {
      return Number(b.priority - a.priority);
    }
    return Number(b.maxPrice - a.maxPrice);
  });

  // 2) Determine the clearing price
  let tokensAccumulated = 0n;
  let finalPrice = 0n;

  for (const bid of bids) {
    // tokensDemanded = (usdcAmount * TOKEN_SCALE) / maxPrice
    const tokensDemanded = (bid.usdcAmount * TOKEN_SCALE) / bid.maxPrice;

    tokensAccumulated += tokensDemanded;
    if (tokensAccumulated >= totalTokens) {
      finalPrice = bid.maxPrice;
      break;
    }
  }

  // If finalPrice is 0, not enough demand to sell all tokens => "not successful"
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

  // 3) Allocate tokens
  let tokensLeft = totalTokens;
  const allocations = {};

  for (const bid of bids) {
    // If user bid below finalPrice => no tokens
    if (bid.maxPrice < finalPrice) {
      allocations[bid.address] = {
        tokens: 0n,
        usedUSDC: 0n,
        refundedUSDC: bid.usdcAmount
      };
      continue;
    }

    // tokensWanted = (usdcAmount * TOKEN_SCALE) / finalPrice
    let tokensWanted = (bid.usdcAmount * TOKEN_SCALE) / finalPrice;
    if (tokensWanted > tokensLeft) {
      tokensWanted = tokensLeft;
    }

    // usedUSDC = (tokensAllocated * finalPrice) / TOKEN_SCALE
    let usedUSDC = (tokensWanted * finalPrice) / TOKEN_SCALE;

    // Refund leftover USDC. Clamp to 0 if negative or 1.
    let refundedUSDC = bid.usdcAmount - usedUSDC;
    if (refundedUSDC < 2n) {
      refundedUSDC = 0n;
    }

    allocations[bid.address] = {
      tokens: tokensWanted,
      usedUSDC,
      refundedUSDC
    };

    tokensLeft -= tokensWanted;
    if (tokensLeft <= 0n) {
      break;
    }
  }

  // If the loop broke early, ensure leftover bidders get 0 tokens
  if (tokensLeft > 0n) {
    for (const bid of bids) {
      if (!allocations[bid.address]) {
        allocations[bid.address] = {
          tokens: 0n,
          usedUSDC: 0n,
          refundedUSDC: bid.usdcAmount
        };
      }
    }
  }

  return { finalPrice, allocations };
}

// ----------------------------------------------------------------------
//  Read input file (address amount maxPrice priority) => BigInt
// ----------------------------------------------------------------------
function readBidsFromFile(filePath) {
  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split(/\r?\n/);

  const bids = [];
  for (const line of lines) {
    if (!line.trim()) continue; // skip empty lines

    const [address, amountStr, maxPriceStr, priorityStr] = line.trim().split(/\s+/);
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
  const outputFilePath = path.join(__dirname, '../../script/data/auction/allocations.txt');

  const bids = readBidsFromFile(inputFilePath);

  // If we want to sell 1,000 tokens, in 18-decimal:
  //  1000 tokens * 1e18 = 1e21
  const totalTokens = 40_000n * 1_000_000_000_000_000_000n; // 1000 * 1e18 = 1e21

  const { finalPrice, allocations } = runAuction(bids, totalTokens);

  writeOutputToFile(outputFilePath, finalPrice, allocations);

  console.log(`Auction complete. Final Price: $${(finalPrice/USDC_SCALE).toString()}.00. Results written to ${outputFilePath}`);
}

// Execute if called directly (e.g. `node auction-bigint.js`)
if (require.main === module) {
  main();
}

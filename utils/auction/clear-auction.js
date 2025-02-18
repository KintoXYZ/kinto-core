const fs = require('fs');
const path = require('path');

/**
 * A uniform-price auction that uses BigInt for 6-decimal USDC calculations.
 *
 * @param {Object[]} bids - The array of bids.
 * @param {string} bids[].address - Ethereum address of the bidder.
 * @param {bigint} bids[].usdcAmount - The amount of USDC committed (6-decimal integer).
 * @param {bigint} bids[].maxPrice   - The bidder's maximum price per token (also 6-decimal integer).
 * @param {bigint} bids[].priority   - Priority for tie-breaking.
 * @param {bigint} totalTokens       - Total tokens available, in 6-decimal “token units” if partial tokens are allowed.
 *
 * @returns {{
 *   finalPrice: bigint,  // 6-decimal integer, or 0n if auction not successful
 *   allocations: {
 *     [address: string]: {
 *       tokens: bigint,      // number of tokens (6 decimals) allocated
 *       usedUSDC: bigint,    // how much USDC was actually spent
 *       refundedUSDC: bigint // how much USDC was refunded
 *     }
 *   }
 * }}
 */
function runAuction(bids, totalTokens) {
  // 1. Sort bids: highest maxPrice first, then highest priority
  bids.sort((a, b) => {
    if (b.maxPrice === a.maxPrice) {
      // Sort descending by priority
      return Number(b.priority - a.priority);
    }
    // Sort descending by maxPrice
    return Number(b.maxPrice - a.maxPrice);
  });

  // 2. Determine the clearing price by accumulating demanded tokens
  let tokensAccumulated = 0n;
  let finalPrice = 0n;

  for (const bid of bids) {
    // tokensDemanded = usdcAmount / maxPrice in a “token scale.”  
    // But to do fractional tokens with BigInt, we need a tokenScale factor.  
    // Let's define 1 token = 1,000,000 “token units” (6 decimals).
    const TOKEN_SCALE = 1_000_000n;
    
    // tokensDemanded = (usdcAmount * TOKEN_SCALE) / maxPrice
    const tokensDemanded = (bid.usdcAmount * TOKEN_SCALE) / bid.maxPrice;

    tokensAccumulated += tokensDemanded;
    if (tokensAccumulated >= totalTokens) {
      finalPrice = bid.maxPrice;
      break;
    }
  }

  // If finalPrice is 0n, we never reached totalTokens → auction not successful
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

  // 3. Allocate tokens with finalPrice known
  const allocations = {};
  let tokensLeft = totalTokens;
  const TOKEN_SCALE = 1_000_000n;

  for (const bid of bids) {
    // If bid.maxPrice < finalPrice, user gets 0 tokens, full refund
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

    // If not enough tokens left for full "wanted," do partial
    if (tokensWanted > tokensLeft) {
      tokensWanted = tokensLeft;
    }

    // usedUSDC = (tokensAllocated * finalPrice) / TOKEN_SCALE
    let usedUSDC = (tokensWanted * finalPrice) / TOKEN_SCALE;

    // refundedUSDC = usdcAmount - usedUSDC  (clamp to 0)
    let refundedUSDC = bid.usdcAmount - usedUSDC;
    if (refundedUSDC < 0n) {
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

  // If we broke early, ensure remaining bidders get 0 tokens if not set
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
//  Reading the input file (address amount maxPrice priority) as BigInt
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

    // Convert to BigInt
    const usdcAmount = BigInt(amountStr);
    const maxPrice   = BigInt(maxPriceStr);
    const priority   = BigInt(priorityStr);

    bids.push({ address, usdcAmount, maxPrice, priority });
  }
  return bids;
}

// ----------------------------------------------------------------------
//  Writing the output file
// ----------------------------------------------------------------------
function writeOutputToFile(filePath, finalPrice, allocations) {
  // We'll create a text file with finalPrice on the first line,
  // then a line for each bidder with their address, tokens, usedUSDC, refundedUSDC

  let output = `Final Price: ${finalPrice.toString()}\n\nAllocations:\n`;

  for (const address in allocations) {
    const { tokens, usedUSDC, refundedUSDC } = allocations[address];
    output += `${address} ${tokens.toString()} ${usedUSDC.toString()} ${refundedUSDC.toString()}\n`;
  }

  fs.writeFileSync(filePath, output, 'utf-8');
}

// ----------------------------------------------------------------------
//  Main Execution
// ----------------------------------------------------------------------
function main() {
  const inputFilePath = path.join(__dirname, '../../script/data/auction/bids.txt');
  const outputFilePath = path.join(__dirname, '../../script/data/auction/allocations.txt');

  // 1) Read the bids as BigInts
  const bids = readBidsFromFile(inputFilePath);

  // 2) totalTokens as BigInt (in 6 decimals if partial tokens are allowed)
  // For example, if you have 1000.000000 tokens, that is:
  const totalTokens = 1_000_000_000_000n;  // 1000 tokens * 1,000,000 (6 decimals) = 1,000,000,000,000

  // 3) Run the auction
  const { finalPrice, allocations } = runAuction(bids, totalTokens);

  // 4) Write results
  writeOutputToFile(outputFilePath, finalPrice, allocations);

  console.log(`Auction complete. Results written to ${outputFilePath}`);
}

// If you want to run directly from CLI: "node auction-bigint.js"
if (require.main === module) {
  main();
}

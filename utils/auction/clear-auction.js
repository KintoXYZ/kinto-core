const fs = require('fs');
const path = require('path');

/**
 * Runs a uniform-price auction and returns:
 *  - The final clearing price
 *  - How many tokens each user gets
 *  - How much USDC is refunded to each user
 *
 * @param {Object[]} bids           Array of bid objects.
 * @param {string}   bids[].address Ethereum address of bidder (unique ID).
 * @param {number}   bids[].usdcAmount  Amount of USDC the user commits.
 * @param {number}   bids[].maxPrice    Maximum price per token the user is willing to pay.
 * @param {number}   bids[].priority    Priority for tie-breaking (higher is better).
 * @param {number}   totalTokens        Total number of tokens available in the auction.
 * @returns {{
 *   finalPrice: number,
 *   allocations: {
 *     [address: string]: {
 *       tokens: number,
 *       usedUSDC: number,
 *       refundedUSDC: number
 *     }
 *   }
 * }}
 */
function runAuction(bids, totalTokens) {
  // --- 1. Sort bids by (maxPrice desc, priority desc) ---
  bids.sort((a, b) => {
    // If maxPrice is the same, compare priority
    if (b.maxPrice === a.maxPrice) {
      return b.priority - a.priority;
    }
    // Otherwise compare by maxPrice
    return b.maxPrice - a.maxPrice;
  });

  // --- 2. Find the clearing price ---
  let tokensAccumulated = 0;
  let finalPrice = 0;
  for (let i = 0; i < bids.length; i++) {
    const bid = bids[i];
    const tokensDemanded = bid.usdcAmount / bid.maxPrice; 
    tokensAccumulated += tokensDemanded;
    
    if (tokensAccumulated >= totalTokens) {
      // As soon as we exceed the totalTokens,
      // the current bid's maxPrice sets the clearing price
      finalPrice = bid.maxPrice;
      break;
    }
  }

  // If finalPrice is 0, it means we never reached totalTokens
  // -> Auction not successful
  if (finalPrice === 0) {
    // Everyone is refunded fully
    const allocations = {};
    for (const bid of bids) {
      allocations[bid.address] = {
        tokens: 0,
        usedUSDC: 0,
        refundedUSDC: bid.usdcAmount
      };
    }
    return {
      finalPrice: 0,
      allocations
    };
  }

  // --- 3. Allocate tokens to each user based on finalPrice ---
  // We do a second pass to figure out exactly how many tokens each user gets,
  // especially for the last "partial" fill if we don't need their entire demand.
  let tokensLeft = totalTokens;
  const allocations = {};

  for (const bid of bids) {
    // Anyone whose maxPrice is below finalPrice gets nothing
    if (bid.maxPrice < finalPrice) {
      allocations[bid.address] = {
        tokens: 0,
        usedUSDC: 0,
        refundedUSDC: bid.usdcAmount
      };
      continue;
    }

    // Otherwise, user is willing to pay finalPrice:
    // The number of tokens they'd *like* to buy at finalPrice
    const tokensWanted = bid.usdcAmount / finalPrice;

    // If we don't have enough tokens left for their full "want," they get partial
    const tokensAllocated = (tokensWanted > tokensLeft) ? tokensLeft : tokensWanted;
    
    // How much USDC does the user actually pay?
    const usedUSDC = tokensAllocated * finalPrice;

    // Refund the rest
    const refundedUSDC = bid.usdcAmount - usedUSDC;

    allocations[bid.address] = {
      tokens: tokensAllocated,
      usedUSDC: usedUSDC,
      refundedUSDC: refundedUSDC
    };

    // Decrease the pool of tokens left
    tokensLeft -= tokensAllocated;

    // If we've allocated all tokens, break early
    if (tokensLeft <= 0) {
      break;
    }
  }

  // For any remaining bidders (if the final fill ended early),
  // they did not get tokens (and thus are refunded in full).
  if (tokensLeft > 0) {
    // In theory, if `tokensLeft > 0`, that would suggest
    // a partial or incomplete auction. However, we found finalPrice
    // from the step above, so let's just ensure that
    // all remaining users after we break are also accounted for:
    for (const bid of bids) {
      // If not yet in allocations, user gets 0 tokens
      if (!allocations[bid.address]) {
        allocations[bid.address] = {
          tokens: 0,
          usedUSDC: 0,
          refundedUSDC: bid.usdcAmount
        };
      }
    }
  }

  return {
    finalPrice,
    allocations
  };
}

// ------------------------------
// 2) Read input file
// ------------------------------
function readBidsFromFile(filePath) {
  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split(/\r?\n/);

  const bids = [];
  for (const line of lines) {
    // Skip empty lines
    if (!line.trim()) {
      continue;
    }

    const [address, amountStr, maxPriceStr, priorityStr] = line.trim().split(/\s+/);
    if (!address || !amountStr || !maxPriceStr || !priorityStr) {
      // If there's a malformed line, skip or handle error
      continue;
    }

    // Convert strings to numbers
    const usdcAmount = Number(amountStr);
    const maxPrice = Number(maxPriceStr);
    const priority = Number(priorityStr);

    // Push to array
    bids.push({
      address,
      usdcAmount,
      maxPrice,
      priority
    });
  }
  return bids;
}

// ------------------------------
// 3) Write results to output file
// ------------------------------
function writeOutputToFile(filePath, finalPrice, allocations) {
  // We can build a string or JSON. Let's do a text-based format:
  let output = '';

  // 1) Final price
  output += `Final Price: ${finalPrice}\n`;
  output += `\nAllocations:\n`;

  // 2) Each user’s allocation
  // format: address tokens usedUSDC refundedUSDC
  for (const address in allocations) {
    const { tokens, usedUSDC, refundedUSDC } = allocations[address];
    output += `${address} ${tokens} ${usedUSDC} ${refundedUSDC}\n`;
  }

  fs.writeFileSync(filePath, output, 'utf-8');
}

// ------------------------------
// 4) Main Logic
// ------------------------------
function main() {
  const inputFilePath = path.join(__dirname, './script/data/auction/bids.txt');
  const outputFilePath = path.join(__dirname, './script/data/auction/allocations.txt');

  // Read the bids
  const bids = readBidsFromFile(inputFilePath);

  // Choose how many tokens are available for the auction
  const totalTokens = 1_000_000; // 

  // Run the auction
  const { finalPrice, allocations } = runAuction(bids, totalTokens);

  // Write results
  writeOutputToFile(outputFilePath, finalPrice, allocations);

  console.log(`Auction complete. Results written to ${outputFilePath}`);
}

// Run main if called directly:
if (require.main === module) {
  main();
}

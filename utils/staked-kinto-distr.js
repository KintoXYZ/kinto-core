const fs = require('fs');
const path = require('path');

// Input and output file paths
const inputFilePath = path.join(__dirname, '../script/data/auction/allocations.txt');
const outputFilePath = path.join(__dirname, '../script/data/staked_kinto_distribution.json');

// Read the input file
const input = fs.readFileSync(inputFilePath, 'utf8');

// Process each line
const lines = input.split('\n');
const output = {};
let totalKTokens = BigInt(0);
let totalStakedKTokens = BigInt(0);
let userCount = 0;

lines.forEach(line => {
  // Skip empty lines
  if (!line.trim()) return;
  
  // Parse the line: address allocation [other values]
  const parts = line.trim().split(/\s+/);
  if (parts.length < 2) return;
  
  const address = parts[0];
  const kAllocation = BigInt(parts[1]); // K token allocation in wei (18 decimals)
  
  // Calculate StakedKinto amount (25% of K amount)
  const stakedKAmount = (kAllocation * BigInt(25)) / BigInt(100);
  
  // Only include users with non-zero allocation
  if (stakedKAmount > 0) {
    output[address] = stakedKAmount.toString();
    totalKTokens += kAllocation;
    totalStakedKTokens += stakedKAmount;
    userCount++;
  }
});

// Write the output to a JSON file
fs.writeFileSync(outputFilePath, JSON.stringify(output, null, 2));

// Log statistics
console.log(`Conversion complete. Processed ${userCount} users.`);
console.log(`Total K tokens allocated: ${totalKTokens.toString()} (${Number(totalKTokens) / 1e18} K)`);
console.log(`Total StakedKinto tokens to distribute: ${totalStakedKTokens.toString()} (${Number(totalStakedKTokens) / 1e18} sK)`);
console.log(`Output saved to: ${outputFilePath}`);
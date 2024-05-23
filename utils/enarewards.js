const fs = require('fs');

// Read the input JSON file
const rawData = fs.readFileSync('./script/data/enarewards.json');
const data = JSON.parse(rawData);

// Extract amounts and wallets
const amounts = data.enaRewardsUSD;
const wallets = data.wallets;

// Convert amounts to BigInt
const amountsBigInt = amounts.map(amount => BigInt(Math.round(amount * 1000000))); // Scale up to handle decimals as integers

// Calculate the total amount in USD (scaled up)
const totalUSDBigInt = amountsBigInt.reduce((acc, val) => acc + val, BigInt(0));

// Total amount of tokens to distribute
const totalTokens = BigInt("23952950190000000000000");

// Calculate the share for each wallet in tokens
const shares = {};
let totalDistributedTokens = BigInt(0);
for (let i = 0; i < wallets.length; i++) {
    const wallet = wallets[i];
    const amount = amountsBigInt[i];
    const share = (amount * totalTokens) / totalUSDBigInt; // Calculate share in tokens
    shares[wallet] = share.toString(); // Convert to string to handle large numbers
    totalDistributedTokens += share;
}

// Check if total distributed tokens exceed the total tokens available
if (totalDistributedTokens > totalTokens) {
    throw new Error('Total distributed tokens exceed the total available tokens.');
}

// Write the results to a new JSON file
const outputData = JSON.stringify(shares, null, 2);
fs.writeFileSync('./script/data/enarewardsfinal.json', outputData);

console.log('Shares calculated and written to shares.json');

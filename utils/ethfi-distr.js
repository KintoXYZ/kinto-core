const fs = require('fs');
const csv = require('csv-parse/sync');

// Read the CSV file
const input = fs.readFileSync('./script/data/ETHFI_finalv2_distribution.csv', 'utf8');

// Parse the CSV data
const records = csv.parse(input, {
  columns: true,
  skip_empty_lines: true
});

// Create the output object
const output = {};
let totalTokens = 0n;

records.forEach(record => {
  console.log('record:', record)
  const wallet = record['wallet'];
  console.log('wallet:', wallet)
  const amountStr = record['ETHFI'];
  // Remove the comma and convert to cents (multiply by 100)
  // 5,294.84289046560000000
  const valueInCents = BigInt(Math.round(parseFloat(amountStr.replace(",", "")) * 1e17));

  // Multiply by 10 to get to 1e18 (since we're already at 1e17 cents)
  const amount = valueInCents * BigInt(10);
  console.log('amount:', amount)

  totalTokens += amount;
  console.log('totalTokens:', totalTokens)

  if (wallet && amount && amount > 0) {
    output[wallet] = amount.toString();
  }
});

console.log('totalTokens:', totalTokens)

// Write the output to a JSON file
fs.writeFileSync('./script/data/ETHFI_finalv2_distribution.json', JSON.stringify(output, null, 2));

console.log('Conversion complete. Check output.json for the result.');

const fs = require('fs');
const csv = require('csv-parse/sync');

// Read the CSV file
const input = fs.readFileSync('./script/data/weETH_final_distribution.csv', 'utf8');

// Parse the CSV data
const records = csv.parse(input, {
  columns: true,
  skip_empty_lines: true
});

// Create the output object
const output = {};
let totalPercent = 0;

records.forEach(record => {
  console.log('record:', record)
  const wallet = record['Kinto Wallet'];
  console.log('wallet:', wallet)
  const rewardPercent = record['reward %'];
  totalPercent += parseFloat(rewardPercent);

  if (wallet && rewardPercent && rewardPercent > 0) {
    // Convert percentage to wei (assuming 18 decimal places)
    const rewardInWei = BigInt(Math.round(parseFloat(rewardPercent) * 1e16)).toString();
    output[wallet] = rewardInWei;
  }
});

console.log('totalPercent:', totalPercent)

// Write the output to a JSON file
fs.writeFileSync('./script/data/weETH_final_distribution.json', JSON.stringify(output, null, 2));

console.log('Conversion complete. Check output.json for the result.');

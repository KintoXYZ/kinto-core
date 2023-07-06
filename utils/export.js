const fs = require('fs');
const path = require('path');
const execSync = require('child_process').execSync;

const dirPath = './src';  // Replace with your actual directory path
const files = fs.readdirSync(dirPath);

let contracts = {};

const network = process.argv[2];
console.log('Exporting contracts for network:', network);

const addresses = JSON.parse(fs.readFileSync(`./artifacts/addresses-${network}.json`, 'utf-8'));

for (let i = 0; i < files.length; i++) {
  const filePath = path.join(dirPath, files[i]);
  const fileExt = path.extname(filePath);
  
  if (fileExt === '.sol') { // Ensure we only process .sol files
    const contractName = path.basename(filePath, '.sol');
    const cmd = `forge inspect ${contractName} abi`;
    const result = execSync(cmd).toString();
    
    console.log('Exported:', contractName, 'ABI');
    
    const jsonObject = JSON.parse(result);
    const address = addresses[contractName];
    if (!address || address.length < 8) {
      console.error('MISSING ADDRESS FOR', contractName);
    }
    contracts[contractName] = {"abi": jsonObject, "address": address};
  }
}

const jsonString = JSON.stringify(contracts);
fs.writeFileSync(`./artifacts/${network}.json`, jsonString);
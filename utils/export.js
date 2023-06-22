const fs = require('fs');
const path = require('path');
const execSync = require('child_process').execSync;

const dirPath = './src';  // Replace with your actual directory path
const files = fs.readdirSync(dirPath);

let contracts = {};

for (let i = 0; i < files.length; i++) {
  const filePath = path.join(dirPath, files[i]);
  const fileExt = path.extname(filePath);
  
  if (fileExt === '.sol') { // Ensure we only process .sol files
    const contractName = path.basename(filePath, '.sol');
    const cmd = `forge inspect ${contractName} abi`;
    const result = execSync(cmd).toString();
    
    console.log('Exported:', contractName, 'ABI');
    
    const jsonObject = JSON.parse(result);
    contracts[contractName] = {"abi": jsonObject};
  }
}

const jsonString = JSON.stringify(contracts);
fs.writeFileSync('./artifacts/42888.json', jsonString);
const fs = require('fs');
const path = require('path');
const execSync = require('child_process').execSync;

const dirPath = './src';  // Replace with your actual directory path
const network = process.argv[2];
console.log(`Exporting contracts for network: ${network}\n`);

const addresses = JSON.parse(fs.readFileSync(`./test/artifacts/${network}/addresses.json`, 'utf-8'));
let contracts = {};


/**
 * Processes a single .sol to extract its ABI and address.
 * @param {string} filePath - path of the Solidity file.
 * @param {string} contractName - name of the contract.
 */
function processSolidityFile(filePath, contractName) {
  const cmd = `forge inspect ${filePath}:${contractName} abi`;
  const result = execSync(cmd).toString();
  const jsonObject = JSON.parse(result);
  console.log(`Processing: ${contractName}`);
  let address = addresses[contractName];
  if ((!address || address.length < 8) && contractName !== 'KintoWallet' && contractName !== 'IBridge' && contractName !== 'IController' && contractName !== 'IConnector' && contractName !== 'ISocket' && contractName !== 'IHook' && contractName !== 'ISocket' && contractName !== 'BridgedToken' && contractName !== 'AccessPoint') {
    console.error(`* Missing address for ${contractName}`);
  } else {
    console.log(`Exported: ${contractName} ABI`);
    contracts[contractName] = { abi: jsonObject, address: address };
  }
}

/**
 * Processes a directory containing .sol files.
 * @param {string} dir - directory to process.
 */
function processDirectory(dir) {
  const dirFiles = fs.readdirSync(dir);
  dirFiles.forEach(file => {
    const filePath = path.join(dir, file);
    const fileExt = path.extname(filePath);

    if (fileExt === '.sol') {
      const contractName = path.basename(filePath, '.sol');
      if (!filePath.includes('Structs.sol')) {

        processSolidityFile(filePath, contractName);
      }
    }
    if (fileExt === '' && filePath.includes('access/workflows')) {
      processDirectory(filePath);
    }
  });
}

/**
 * Processes all .sol files in the specified directory and its subdirectories.
 */
function processFiles() {
  const files = fs.readdirSync(dirPath);
  files.forEach(file => {
    const filePath = path.join(dirPath, file);
    const fileExt = path.extname(filePath);
    console.log('Processing file:', filePath);
    if (fileExt === '' && !filePath.includes('interfaces') && !filePath.includes('libraries')) {
      processDirectory(filePath);
    } else if (fileExt === '.sol') {
      const contractName = path.basename(filePath, '.sol');
      processSolidityFile(filePath, contractName);
    }
  });
}

processFiles();

const jsonString = JSON.stringify({ contracts: contracts }, null, 2);
fs.writeFileSync(`./artifacts/${network}.json`, jsonString);

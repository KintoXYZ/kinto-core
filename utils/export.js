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
  const cmd = `forge inspect ${contractName} abi`;
  const result = execSync(cmd).toString();
  console.log(`Exported: ${contractName} ABI`);

  const jsonObject = JSON.parse(result);
  let address = addresses[contractName];
  if (!address || address.length < 8) console.error(`* Missing address for ${contractName}`);
  contracts[contractName] = { abi: jsonObject, address: address };
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
      processSolidityFile(filePath, contractName);
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


// const files = fs.readdirSync(dirPath);


// // Loop through all directories in src
// for (let i = 0; i < files.length; i++) {
//   const filePath = path.join(dirPath, files[i]);
//   const fileExt = path.extname(filePath);
//   if (fileExt === '' && !filePath.includes('interfaces') && !filePath.includes('libraries')) { // Ensure we only process directories
//     const dirFiles = fs.readdirSync(filePath);
//     for (let j = 0; j < dirFiles.length; j++) {
//       const dirFilePath = path.join(filePath, dirFiles[j]);
//       const dirFileExt = path.extname(dirFilePath);

//       if (dirFileExt === '.sol') { // Ensure we only process .sol files
//         const contractName = path.basename(dirFilePath, '.sol');
//         const cmd = `forge inspect ${contractName} abi`;
//         const result = execSync(cmd).toString();
//         console.log('Exported:', contractName, 'ABI');
//         const jsonObject = JSON.parse(result);
//         let address = addresses[contractName];
//         if (!address || address.length < 8) {
//           address = "0x0000000000000000000000000000000000000000";
//           console.error('MISSING ADDRESS FOR', contractName);
//         }
//         contracts[contractName] = {"abi": jsonObject, "address": address};
//       }
//     }
//   }
// }


// for (let i = 0; i < files.length; i++) {
//   const filePath = path.join(dirPath, files[i]);
//   const fileExt = path.extname(filePath);
  
//   if (fileExt === '.sol') { // Ensure we only process .sol files
//     const contractName = path.basename(filePath, '.sol');
//     const cmd = `forge inspect ${contractName} abi`;
//     const result = execSync(cmd).toString();
    
//     console.log('Exported:', contractName, 'ABI');
    
//     const jsonObject = JSON.parse(result);
//     let address = addresses[contractName];
//     if (!address || address.length < 8) {
//       address = '0x0000000000000000000000000000000000000000';
//       console.error('MISSING ADDRESS FOR', contractName);
//     }
//     contracts[contractName] = {"abi": jsonObject, "address": address};
//   }
// }

// const jsonString = JSON.stringify({"contracts": contracts});
// fs.writeFileSync(`./artifacts/${network}.json`, jsonString);
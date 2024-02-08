const {bn254} = require('@noble/curves/bn254');

function toHexString(number, length = 64) {
  return number.toString(16).padStart(length, '0');
}

async function signUserOperation(messagePart0, messagePart1, privateKeyHex) {
  // Convert the private key from hex string to BigInt
  const privateKey = BigInt(`0x${privateKeyHex}`);

  // Hash the message to get a 32-byte message hash
  // Note: In a real implementation, you should use a proper hash function like SHA-256
  // const messageHash = bls12_381.utils.sha256(message);
  
  // Convert each part to a hex string
  const part0Hex = toHexString(BigInt(messagePart0));
  const part1Hex = toHexString(BigInt(messagePart1));

  // Concatenate the hex strings (without the '0x' prefix of the second part)
  const msgHash = part0Hex + part1Hex.slice(2);
  console.log("msgHash", msgHash);

  // Sign the message hash with the BLS private key
  const signature = await bn254.sign(msgHash, privateKey);

  // Convert the signature to hex format for easier handling
  // const signatureHex = `0x${signature.r.toString(16)}${signature.s.toString(16)}`;
  const signatureHex = signature.toCompactHex();

  console.log(signatureHex.length);
  return signatureHex;
}

// Check if the private key and message are provided as command line arguments
if (process.argv.length < 5) {
  console.error('Usage: node signUserOperation.js <message part 0> <message part 1> <privateKeyHex>');
  process.exit(1);
}

const messagePart0 = process.argv[2];
const messagePart1 = process.argv[3];
const privateKeyHex = process.argv[4];

signUserOperation(messagePart0, messagePart1, privateKeyHex)
  .then(signatureHex => {
    console.log('Signature:', signatureHex);
    // Now you can use this signature in your Ethereum transaction
  })
  .catch(console.error);


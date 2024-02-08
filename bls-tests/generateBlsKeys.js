const {bn254} = require('@noble/curves/bn254');

// FIXME: the isue here is that the library noble/curves/bn254 does not yet support G2 which is what is being used in
// BLS.sol (used by the eth-infinitism BLS Aggregator implementation). There's an GH issue here: https://github.com/paulmillr/noble-curves/issues/70
async function generateBlsKeyPair() {
    // Generate private key
    const privateKey = bn254.utils.randomPrivateKey();
    console.log(`Private Key: ${privateKey}`);
    console.log(`Private Key: ${Buffer.from(privateKey).toString('hex')}`);
    console.log(`Is valid private key?: ${bn254.utils.isValidPrivateKey(Buffer.from(privateKey).toString('hex'))}`);
    

    // Generate public key from the private key
    const compressedPublicKey = await bn254.getPublicKey(privateKey);
    const uncompressedPublicKey = await bn254.getPublicKey(privateKey, false);
    console.log(`Public Key (compressed): ${Buffer.from(compressedPublicKey).toString('hex')}`);
    console.log(`Public Key (uncompressed): ${Buffer.from(uncompressedPublicKey).toString('hex')}`);

    // Decode uncompressedPublicKey to get the components x and y to get the uint256[4] format that we need in Solidity
    const components = decodePublicKey(uncompressedPublicKey);

    // x1, x2, y1 and y2 are the coordinates of the public key
    console.log(`x1, x2, y1, y2: ${components[0]}, ${components[1]}, ${components[2]}, ${components[3]}`);
}

function decodePublicKey(publicKeyBytes) {
    if (publicKeyBytes.length !== 65) {
        throw new Error('Unexpected public key length');
    }

    // Remove the 0x04 prefix
    const publicKeyWithoutPrefix = publicKeyBytes.slice(1);

    // Split the publicKeyWithoutPrefix into x and y coordinates (32 bytes each)
    const xBytes = publicKeyWithoutPrefix.slice(0, 32);
    const yBytes = publicKeyWithoutPrefix.slice(32);

    const x0 = BigInt('0x' + Buffer.from(xBytes).toString('hex'));
    const x1 = BigInt(0); // TODO: how?
    const y0 = BigInt('0x' + Buffer.from(yBytes).toString('hex'));
    const y1 = BigInt(0); // TODO: how?

    // Convert to hex strings for Solidity
    const x0Hex = '0x' + x0.toString(16);
    const x1Hex = '0x' + x1.toString(16);
    const y0Hex = '0x' + y0.toString(16);
    const y1Hex = '0x' + y1.toString(16);

    // Return the uint256[4] array
    return [x0Hex, x1Hex, y0Hex, y1Hex];
}

generateBlsKeyPair().catch(console.error);

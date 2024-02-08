const {bn254} = require('@noble/curves/bn254');

// TODO: use aggregateShortSignatures or aggregatePublicKeys from BN254?
async function aggregatePublicKeys(publicKeys) {
    // Convert hex strings to point objects and ensure they are valid
    const publicKeyPoints = publicKeys.map(key => bn254.ProjectivePoint.fromHex(key));
    // const publicKeyPoints = publicKeys.map(key => bn254.ProjectivePoint.fromHex(key)).filter(point => point.assertValidity());
    
    console.log(publicKeyPoints);
    // Aggregate public keys by summing them
    const aggregatedPublicKey = publicKeyPoints.reduce((sum, current) => sum.add(current), bn254.ProjectivePoint.ZERO);
  
    // Convert the aggregated public key back to hex or another preferred format
    const aggregatedPublicKeyHex = aggregatedPublicKey.toHex();
    console.log(`Aggregated Public Key: ${aggregatedPublicKeyHex}`);
  
    return aggregatedPublicKeyHex;
  }
  
// Process command line arguments, skipping the first two (node and script path)
const publicKeys = process.argv.slice(2);

if (publicKeys.length === 0) {
    console.error("Usage: node aggregatePublicKeys.js <publicKey1> <publicKey2> ...");
    process.exit(1);
}

// Example usage
(async () => {
    await aggregatePublicKeys(publicKeys);
})().catch(console.error);


import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";

// ESM-friendly __dirname
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Relative paths or absolute paths as needed
const ALLOCATIONS_FILE = path.join(__dirname, "../../script/data/auction/allocations.txt");
const OUTPUT_JSON = path.join(__dirname, "../../script/data/auction/merkle-tree.json");

async function main() {
  // 1) Read lines from allocations.txt
  const content = fs.readFileSync(ALLOCATIONS_FILE, "utf-8");

  // Split into non-empty lines
  const lines = content.split(/\r?\n/).filter(line => line.trim().length > 0);

  // 2) Build the "values" array for Merkle tree
  //    Each element is [address, saleTokenAllocation, usdcAllocation]
  const values = [];
  for (const line of lines) {
    const [address, saleAlloc, spentUsdcAlloc, usdcAlloc] = line.trim().split(/\s+/);

    if (!address || !saleAlloc || !spentUsdcAlloc || !usdcAlloc) {
      console.warn(`Skipping malformed line: "${line}"`);
      continue;
    }

    // For the tree, we only need [address, saleAlloc, usdcAlloc],
    // matching ["address","uint256","uint256"] in the schema.
    values.push([address, saleAlloc, usdcAlloc]);
  }

  if (values.length === 0) {
    console.error("No allocations found. Exiting.");
    process.exit(1);
  }

  // 3) Create the Merkle tree
  const tree = StandardMerkleTree.of(values, ["address", "uint256", "uint256"]);

  // 4) Print the Merkle root (paste this into your contract)
  console.log("Merkle Root:", tree.root);

  // 5) Build a "claims" object that maps each user address to { saleAlloc, usdcAlloc, proof }
  const claims = {};
  for (const [i, v] of tree.entries()) {
    const proof = tree.getProof(i);
    const [addr, saleAlloc, usdcAlloc] = v;
    claims[addr] = {
      saleAlloc,
      usdcAlloc,
      proof,
    };
  }

  // 6) Construct a final JSON output that contains:
  //    - The Merkle root
  //    - The claims object
  const fullOutput = {
    merkleRoot: tree.root,
    claims,
  };

  fs.writeFileSync(OUTPUT_JSON, JSON.stringify(fullOutput, null, 2), "utf-8");
  console.log(`Merkle tree and per-address claims saved to ${OUTPUT_JSON}`);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});

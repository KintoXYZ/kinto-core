import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";

// ESM-friendly __dirname
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Relative path to your allocations file.
// Adjust if needed, or make it an absolute path.
const ALLOCATIONS_FILE = path.join(__dirname, "../../script/data/auction/allocations.txt");

// JSON file to dump the entire Merkle tree.
const OUTPUT_JSON = path.join(__dirname, "../../script/data/auction/merkle-tree.json");

async function main() {
  // 1) Read lines from allocations.txt
  const content = fs.readFileSync(ALLOCATIONS_FILE, "utf-8");

  // Split into non-empty lines
  const lines = content.split(/\r?\n/).filter(line => line.trim().length > 0);

  // 2) Build the "values" array for Merkle tree
  // Each element is [ userAddress, saleTokenAllocation, usdcAllocation ]
  // all as strings, matching ["address","uint256","uint256"] in the tree schema.
  const values = [];
  for (const line of lines) {
    const [address, saleAlloc, usdcAlloc] = line.trim().split(/\s+/);
    if (!address || !saleAlloc || !usdcAlloc) {
      console.warn(`Skipping malformed line: "${line}"`);
      continue;
    }

    // Push as an array: [ string, string, string ]
    values.push([address, saleAlloc, usdcAlloc]);
  }

  if (values.length === 0) {
    console.error("No allocations found. Exiting.");
    process.exit(1);
  }

  // 3) Create the Merkle tree
  // The schema must match the types: ["address", "uint256", "uint256"]
  const tree = StandardMerkleTree.of(values, ["address", "uint256", "uint256"]);

  // 4) Print the Merkle root (paste this into your contract)
  console.log("Merkle Root:", tree.root);

  // 5) Write the entire tree to a JSON file (for off-chain reference)
  fs.writeFileSync(OUTPUT_JSON, JSON.stringify(tree.dump()), "utf-8");
  console.log(`Merkle tree dumped to ${OUTPUT_JSON}`);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});

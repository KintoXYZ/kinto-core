import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { StandardMerkleTree } from "@openzeppelin/merkle-tree";

// ESM-friendly __dirname
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Relative paths or absolute paths as needed
const ALLOCATIONS_FILE = path.join(__dirname, "../../script/data/auction/allocations.txt");
const BIDS_FILE = path.join(__dirname, "../../script/data/auction/bids.txt");
const OUTPUT_JSON = path.join(__dirname, "../../script/data/auction/merkle-tree.json");
const OUTPUT_CSV = path.join(__dirname, "../../script/data/auction/allocations.csv");

async function main() {
  // 1) Read lines from allocations.txt
  const content = fs.readFileSync(ALLOCATIONS_FILE, "utf-8");

  // Split into non-empty lines
  let lines = content.split(/\r?\n/).filter(line => line.trim().length > 0);

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

  // Split into non-empty lines
  lines = fs.readFileSync(BIDS_FILE, "utf-8").split(/\r?\n/).filter(line => line.trim().length > 0);

  const bids = [];
  for (const line of lines) {
    const [address, amount, price, priority] = line.trim().split(/\s+/);

    if (!address || !amount || !price || !priority) {
      console.warn(`Skipping malformed line: "${line}"`);
      continue;
    }

    bids.push([address, amount, price]);
  }

  // 5) Build a "claims" object that maps each user address to { saleAlloc, usdcAlloc, proof }
  const claims = {};
  const validLines = []; // Keep track of valid lines for CSV
  for (const [i, v] of tree.entries()) {
    const proof = tree.getProof(i);
    const [addr, saleAlloc, usdcAlloc] = v;
    let bid = bids.filter(bid => bid[0] === addr)[0];
    claims[addr.toLowerCase()] = {
      bidAmount: bid[1],
      bidPrice: bid[2] / 1e6,
      saleAlloc,
      usdcAlloc,
      proof,
      addr,
    };

    // Keep full info for CSV output
    validLines.push({
      bidAmount: bid[1],
      bidPrice: bid[2] / 1e6,
      saleAlloc,
      usdcAlloc,
      address: addr,
    });
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

  // 7) Write a CSV file (no proofs, just address + saleAlloc + spentUsdcAlloc + usdcAlloc)
  const csvHeader = "address,bidAmount,bidPrice,saleAlloc,usdcAlloc";
  const csvRows = [csvHeader];
  for (const lineObj of validLines) {
    const { address, saleAlloc, bidAmount, usdcAlloc, bidPrice } = lineObj;
    csvRows.push(`${address},${bidAmount},${bidPrice},${saleAlloc},${usdcAlloc}`);
  }

  fs.writeFileSync(OUTPUT_CSV, csvRows.join("\n"), "utf-8");
  console.log(`Allocations CSV (no proofs) saved to: ${OUTPUT_CSV}`);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});

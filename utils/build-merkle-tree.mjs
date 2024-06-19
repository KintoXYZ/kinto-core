import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import fs from "fs";

// (1)
const values = [
  ["0x6813Eb9362372EEF6200f3b1dbC3f819671cBA69", "1000000000000000000"],
  ["0x6813Eb9362372EEF6200f3b1dbC3f819671cBA69", "1000000000000000000"],
  ["0x6813Eb9362372EEF6200f3b1dbC3f819671cBA69", "1000000000000000000"],
  ["0x2222222222222222222222222222222222222222", "2500000000000000000"]
];

// (2)
const tree = StandardMerkleTree.of(values, ["address", "uint256"]);

// (3)
console.log('Merkle Root:', tree.root);

// (4)
fs.writeFileSync("./test/data/rd-merkle-tree.json", JSON.stringify(tree.dump()));

for (const [i, v] of tree.entries()) {
    const proof = tree.getProof(i);
    console.log('Value:', v);
    console.log('Proof:', proof);
  }

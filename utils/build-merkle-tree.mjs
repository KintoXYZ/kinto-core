import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import fs from "fs";

const values = [
  ["0x6813Eb9362372EEF6200f3b1dbC3f819671cBA69", "1000000000000000000"],
  ["0x6813Eb9362372EEF6200f3b1dbC3f819671cBA69", "1000000000000000000"],
  ["0x6813Eb9362372EEF6200f3b1dbC3f819671cBA69", "1000000000000000000"],
  ["0x2222222222222222222222222222222222222222", "2500000000000000000"]
];

const tree = StandardMerkleTree.of(values, ["address", "uint256"]);

console.log('Merkle Root:', tree.root);

fs.writeFileSync("./test/data/rd-merkle-tree.json", JSON.stringify(tree.dump()));

for (const [i, v] of tree.entries()) {
    const proof = tree.getProof(i);
    console.log('Value:', v);
    console.log('Proof:', proof);
  }

const values2 = [
  ["0x6813Eb9362372EEF6200f3b1dbC3f819671cBA69", "1000000000000000000"],
  ["0x6813Eb9362372EEF6200f3b1dbC3f819671cBA69", "2000000000000000000"]
];

const tree2 = StandardMerkleTree.of(values2, ["address", "uint256"]);

console.log('Merkle Root 2:', tree2.root);

fs.writeFileSync("./test/data/rd-merkle-tree-2.json", JSON.stringify(tree2.dump()));

for (const [i, v] of tree2.entries()) {
    const proof = tree2.getProof(i);
    console.log('Value:', v);
    console.log('Proof:', proof);
  }

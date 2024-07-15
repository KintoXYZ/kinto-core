import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import fs from "fs";

const tree = StandardMerkleTree.load(JSON.parse(fs.readFileSync('./test/data/tree.json', 'utf8')));

console.log('Merkle Root:', tree.root);

const addr = '0x337B9727E78C18b8D5111f787A9ae5Fdc7E54897';

for (const [i, v] of tree.entries()) {
    const proof = tree.getProof(i);
    if(v[0] == addr) {
      console.log('Value:', v);
      console.log('Proof:', proof);
    }
  }

import "dotenv/config";
import {
  ENTRYPOINT_ADDRESS_V07,
  bundlerActions,
  getSenderAddress,
  signUserOperationHashWithECDSA,
  createSmartAccountClient,
} from "permissionless";
import {
  pimlicoBundlerActions,
  pimlicoPaymasterActions,
} from "permissionless/actions/pimlico";
import { mainnet, base, arbitrum, optimism } from "viem/chains";
import { writeFileSync } from "fs";
import { signerToSimpleSmartAccount } from "permissionless/accounts";
import {
  createPimlicoBundlerClient,
  createPimlicoPaymasterClient,
} from "permissionless/clients/pimlico";
import {
  encodeFunctionData,
  http,
  createPublicClient,
  createClient,
  encodePacked,
  createWalletClient,
} from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";

const ACCESS_REGISTRY = "0xA000000eaA652c7023530b603844471294B811c4";

async function callWorkflow(privateKey, pimlicoRpcUrl, nodeRpcUrl) {
  const publicClient = createPublicClient({
    transport: http(nodeRpcUrl),
  });

  const bundlerClient = createClient({
    transport: http(pimlicoRpcUrl),
  })
    .extend(bundlerActions(ENTRYPOINT_ADDRESS_V07))
    .extend(pimlicoBundlerActions(ENTRYPOINT_ADDRESS_V07));

  const paymasterClient = createClient({
    transport: http(pimlicoRpcUrl),
  }).extend(pimlicoPaymasterActions(ENTRYPOINT_ADDRESS_V07));

  const owner = privateKeyToAccount(privateKey);

  const factoryData = encodeFunctionData({
    abi: [
      {
        inputs: [
          { name: "owner", type: "address" },
          { name: "salt", type: "uint256" },
        ],
        name: "createAccount",
        outputs: [{ name: "ret", type: "address" }],
        stateMutability: "nonpayable",
        type: "function",
      },
    ],
    args: [owner.address, 0n],
  });

  console.log("Generated factoryData:", factoryData);
  console.log('owner:', owner.address)

  const senderAddress = await getSenderAddress(publicClient, {
    factory: '0xA000000eaA652c7023530b603844471294B811c4',
    factoryData,
    entryPoint: ENTRYPOINT_ADDRESS_V07,
  });
  console.log("Calculated sender address:", senderAddress);
}

callWorkflow(process.argv[2], process.argv[3], process.argv[4])
  .then(result => console.log(result))
  .catch(err => console.error("Error getting quote:", err));

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
  console.log("owner:", owner.address);

  const senderAddress = await getSenderAddress(publicClient, {
    factory: ACCESS_REGISTRY,
    factoryData,
    entryPoint: ENTRYPOINT_ADDRESS_V07,
  });
  console.log("Calculated sender address:", senderAddress);

  const bytecode = await publicClient.getBytecode({ address: senderAddress })
  let isAccountDeployed = false;
  if(bytecode.length > 0){
    isAccountDeployed = true;
  }
  console.log('isAccountDeployed:', isAccountDeployed)sponsoredUserOperation

  // WethWorkflow
  const target = "0x7F7c594eE170a62d7e7615972831038Cf7d4Fc1A";
  // cast abi-encode "deposit(uint256)" 0.01ether
  const data = "0xb6b55f25000000000000000000000000000000000000000000000000002386f26fc10000";

  const callData = encodeFunctionData({
    abi: [
      {
        inputs: [
          { name: "target", type: "address" },
          { name: "data", type: "bytes" },
        ],
        name: "execute",
        outputs: [{ name: "response", type: "bytes" }],
        stateMutability: "nonpayable",
        type: "function",
      },
    ],
    args: [target, data],
  });

  console.log("Generated callData:", callData);

  const gasPrice = await bundlerClient.getUserOperationGasPrice();

  const userOperation = {
    sender: senderAddress,
    nonce: 0n,
    factory: isAccountDeployed ? undefined : ACCESS_REGISTRY,
    factoryData: isAccountDeployed ? undefined: factoryData,
    callData: callData,
    maxFeePerGas: gasPrice.fast.maxFeePerGas,
    maxPriorityFeePerGas: gasPrice.fast.maxPriorityFeePerGas,
    // dummy signature, needs to be there so the SimpleAccount doesn't immediately revert because of invalid signature length
    signature:
      "0xa15569dd8f8324dbeabf8073fdec36d4b754f53ce5901e283c6de79af177dc94557fa3c9922cd7af2a96ca94402d35c39f266925ee6407aeb32b31d76978d4ba1c",
  };

  const sponsorUserOperationResult = await paymasterClient.sponsorUserOperation(
    {
      userOperation,
    }
  );

  const sponsoredUserOperation = {
    ...userOperation,
    ...sponsorUserOperationResult,
  };

  console.log("Received paymaster sponsor result:", sponsorUserOperationResult);

  const signature = await signUserOperationHashWithECDSA({
    account: owner,
    userOperation: sponsoredUserOperation,
    chainId: publicClient.chain.id,
    entryPoint: ENTRYPOINT_ADDRESS_V07,
  });
  sponsoredUserOperation.signature = signature;

  console.log("Generated signature:", signature);

  const userOperationHash = await bundlerClient.sendUserOperation({
    userOperation: sponsoredUserOperation,
  });

  console.log("Received User Operation hash:", userOperationHash);

  // let's also wait for the userOperation to be included, by continually querying for the receipts
  console.log("Querying for receipts...");
  const receipt = await bundlerClient.waitForUserOperationReceipt({
    hash: userOperationHash,
  });
  const txHash = receipt.receipt.transactionHash;

  console.log(
    `UserOperation included: https://sepolia.etherscan.io/tx/${txHash}`
  );
}

callWorkflow(process.argv[2], process.argv[3], process.argv[4])
  .then((result) => console.log(result))
  .catch((err) => console.error("Error getting quote:", err));

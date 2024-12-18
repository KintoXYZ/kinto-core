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
  getContract,
  encodeFunctionData,
  http,
  createPublicClient,
  createClient,
  encodePacked,
  createWalletClient,
} from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";

const ACCESS_REGISTRY = "0xA000000eaA652c7023530b603844471294B811c4";

async function callWorkflow(
  privateKey: string,
  pimlicoRpcUrl: string,
  nodeRpcUrl: string
): Promise<void> {
  const publicClient = createPublicClient({
    transport: http(nodeRpcUrl),
    chain: arbitrum,
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

  const bytecode = await publicClient.getCode({ address: senderAddress });
  let isAccountDeployed = false;
  if (!!bytecode && bytecode.length > 0) {
    isAccountDeployed = true;
  }
  console.log("isAccountDeployed:", isAccountDeployed);

  // WethWorkflow
  const weth = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
  const wethWorkflow = "0x7F7c594eE170a62d7e7615972831038Cf7d4Fc1A";
  // cast abi-encode "deposit(uint256)" 0.01ether

  const depositCalldata = encodeFunctionData({
    abi: [
      {
        inputs: [{ name: "amount", type: "uint256" }],
        name: "deposit",
        outputs: [],
        stateMutability: "payable",
        type: "function",
      },
    ],
    args: [1n],
  });

  const callData = encodeFunctionData({
    abi: [
      {
        inputs: [
          { name: "target", type: "address" },
          { name: "data", type: "bytes" },
        ],
        name: "execute",
        outputs: [{ name: "response", type: "bytes" }],
        stateMutability: "payable",
        type: "function",
      },
    ],
    args: [wethWorkflow, depositCalldata],
  });

  console.log("Generated callData:", callData);

  // BridgeWorkflow
  const bridgeWorkflow = "0xDd53a659E428A7d5bc472112CD7B4e06cd548D4B";

  // cast abi-encode "bridge((address,uint256,address,(address,uint256,uint256,address,bytes,bytes)))" "(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,1,0x2e2B1c42E38f5af81771e65D87729E57ABD1337a,(0x...,1))"

  const kintoAdmin = "0x2e2B1c42E38f5af81771e65D87729E57ABD1337a";
  const wethVault = "0x4D585D346DFB27b297C37F480a82d4cAB39491Bb";
  const vaultAbi = [
    {
      inputs: [
        { name: "connector", type: "address" },
        { name: "msgGasLimit", type: "uint256" },
        { name: "payloadSize", type: "uint256" },
      ],
      name: "getMinFees",
      outputs: [{ name: "totalFees", type: "uint256" }],
      stateMutability: "nonpayable",
      type: "function",
    },
  ];

  const wethConnector = "0x47469683AEAD0B5EF2c599ff34d55C3D998393Bf";

  const fees = await publicClient.readContract({
    address: wethVault,
    abi: vaultAbi,
    functionName: "getMinFees",
    args: [wethConnector, 500_000, 322],
  });
  console.log("fees:", fees);

  const bridgeCalldata = encodeFunctionData({
    abi: [
      {
        inputs: [
          { name: "asset", type: "address" },
          { name: "amount", type: "uint256" },
          { name: "wallet", type: "address" },
          {
            name: "bridgeData",
            type: "tuple",
            components: [
              { name: "vault", type: "address" },
              { name: "gasFee", type: "uint256" },
              { name: "msgGasLimit", type: "uint256" },
              { name: "connector", type: "address" },
              { name: "execPayload", type: "bytes" },
              { name: "options", type: "bytes" },
            ],
          },
        ],
        name: "bridge",
        outputs: [],
        stateMutability: "payable",
        type: "function",
      },
    ],
    args: [
      weth,
      1n, // Use BigInt for uint256
      kintoAdmin,
      {
        vault: wethVault,
        gasFee: fees,
        msgGasLimit: 500000n, // Use BigInt for uint256
        connector: wethConnector,
        execPayload: "0x", // empty bytes
        options: "0x", // empty bytes
      },
    ],
  });

  console.log("Generated brideCalldata:", bridgeCalldata);

  const executeBatchCalldata = encodeFunctionData({
    abi: [
      {
        inputs: [
          { name: "target", type: "address[]" },
          { name: "data", type: "bytes[]" },
        ],
        name: "executeBatch",
        outputs: [{ name: "response", type: "bytes[]" }],
        stateMutability: "payable",
        type: "function",
      },
    ],
    args: [
      [wethWorkflow, bridgeWorkflow],
      [depositCalldata, bridgeCalldata],
    ],
  });

  console.log("Generated executeBatchCalldata:", executeBatchCalldata);

  const gasPrice = await bundlerClient.getUserOperationGasPrice();

  const accountAbi = [
    {
      inputs: [],
      name: "getNonce",
      outputs: [{ name: "nonce", type: "uint256" }],
      stateMutability: "view",
      type: "function",
    },
  ];

  // Assuming you already have `senderAddress` as the address of the deployed account contract
  const accountNonce = await publicClient.readContract({
    address: senderAddress, // the smart account address
    abi: accountAbi, // ABI of the account to fetch the nonce
    functionName: "getNonce", // assuming getNonce is the function name
  });
  console.log("Account abstraction nonce:", accountNonce);

  const userOperation = {
    sender: senderAddress,
    nonce: accountNonce,
    factory: isAccountDeployed ? undefined : ACCESS_REGISTRY,
    factoryData: isAccountDeployed ? undefined : factoryData,
    callData: executeBatchCalldata,
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

  console.log(`UserOperation included: /tx/${txHash}`);
}

// tsx ./utils/pimlico.ts 0x$DEPLOYER_PRIVATE_KEY $PIMLICO_API_KEY $ARBITRUM_RPC_URL
callWorkflow(process.argv[2], process.argv[3], process.argv[4])
  .then((result) => console.log(result))
  .catch((err) => console.error("Error getting quote:", err));

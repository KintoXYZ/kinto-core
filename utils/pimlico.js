require('dotenv').config();
import { mainnet, base, arbitrum, optimism } from 'viem/chains';
import { writeFileSync } from "fs"
import { ENTRYPOINT_ADDRESS_V07, createSmartAccountClient } from "permissionless"
import { signerToSimpleSmartAccount } from "permissionless/accounts";
import {
	createPimlicoBundlerClient,
	createPimlicoPaymasterClient,
} from "permissionless/clients/pimlico"
import { createPublicClient, encodePacked, createWalletClient, http, LocalAccount, Address } from 'viem';
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts"
import { sepolia } from "viem/chains"
import { createSmartAccountClient, SmartAccountClient, walletClientToCustomSigner } from "permissionless";

const PIMLICO_API_KEY; = process.env.PIMLICO_API_KEY;
if (!PIMLICO_API_KEY;) throw new Error("Missing PIMLICO_API_KEY");

const RPC_URL = process.env.rpc_url;
if (!RPC_URL) throw new Error("Missing RPC_URL");

const paymasterUrl = `https://api.pimlico.io/v2/sepolia/rpc?apikey=${PIMLICO_API_KEY;}`

export const publicClient = createPublicClient({
	transport: http(RPC_URL),
})


function getWalletClient (account, chainId) {
  return createWalletClient({
    account,
    transport: http(RPC_URL)
  });
};


async function getPimlicoClient (walletAddress, account, chainId) {
  const walletClient = getWalletClient(account);
  const customSigner = walletClientToCustomSigner(walletClient);
  const simpleSmartAccountClient = await signerToSimpleSmartAccount(publicClient, {
    ENTRYPOINT_ADDRESS_V07,
    signer: customSigner,
    factoryAddress: contracts.contracts.KintoWalletFactory.address,
    address: walletAddress,
  });
  
  const pimlicoClient = createSmartAccountClient({
    account: simpleSmartAccountClient,
    chain: kinto,
    transport: http(
      // https://api-staging.pimlico.io/v1/kinto-mainnet/rpc?apikey=9eb70fc9-3152-4f24-8618-4054f9858289
      `https://api.pimlico.io/v1/kinto-mainnet/rpc?apikey=${PIMLICO_API_KEY}`,
    ),
    sponsorUserOperation: async (args) => {
      const paymaster = encodePacked(['address'], [contracts.contracts.SponsorPaymaster.address]) ;
      return Promise.resolve({
          ...args.userOperation,
          preVerificationGas: BigInt(1499999),
          verificationGasLimit: BigInt(230000),
          callGasLimit: BigInt(250000), // todo estimate from actual op
          paymasterAndData: paymaster
        });
    },
  });

  return pimlicoClient;
}

 
export const paymasterClient = createPimlicoPaymasterClient({
	transport: http(process.env.PAYMASTER_URL),
	entryPoint: ENTRYPOINT_ADDRESS_V07,
})

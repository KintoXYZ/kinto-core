require('dotenv').config();
const ethers = require('ethers');

/**
 * Get a quote from 0x-API to sell the WETH we just deposited into the contract.
 * @dev you can call this script from CLI with e.g `node ./utils/0x-quotes.js 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497 1000000000000000000`
 * @param {*} sellTokenAddr 
 * @param {*} buyTokenAddr 
 * @param {*} sellAmount 
 * @returns 
 */
const getQuote = async (sellTokenAddr, buyTokenAddr, sellAmount) => {
  const provider = new ethers.InfuraProvider();
  const tokenAbi = ["function symbol() view returns (string)"];
  const sellToken = new ethers.Contract(sellTokenAddr, tokenAbi, provider);
  const buyToken = new ethers.Contract(buyTokenAddr, tokenAbi, provider);
  const sellETH = sellTokenAddr === 0;
  const buyETH = buyTokenAddr === 0;

  console.info(
    ` - Fetch swap quote from 0x-API to sell ${ethers.formatEther(sellAmount)} ${
      sellETH ? "ETH" : await sellToken.symbol()
    } for ${buyETH ? "ETH" : await buyToken.symbol()}...`,
  );
  const qs = createQueryString({
    sellToken: sellToken.target,
    buyToken: buyToken.target,
    sellAmount,
  });
  const API_QUOTE_URL = "https://api.0x.org/swap/v1/quote";
  const quoteUrl = `${API_QUOTE_URL}?${qs}`;
  console.info(`  * Fetching quote ${quoteUrl}...`);
  
  if (!process.env.ZEROEX_API_KEY) throw new Error("ZEROEX_API_KEY not set");
  const response = await fetch(quoteUrl, {
    headers: {
      "0x-api-key": process.env.ZEROEX_API_KEY,
    },
  });
  const quote = await response.json();
  console.info(`  * Received a quote with price ${quote.price}`);
  console.info(`  * Received a quote buy amount of: ${quote.buyAmount}`);
  console.info(`  * Received a quote guaranteed amount of: ${BigInt(quote.guaranteedPrice * quote.sellAmount).toString()}`);
  return quote;
};

const createQueryString = params => {
  return Object.entries(params)
    .map(([k, v]) => `${k}=${v}`)
    .join("&");
};

const sellTokenAddr = process.argv[2];
const buyTokenAddr = process.argv[3];
const sellAmount = process.argv[4];

getQuote(sellTokenAddr, buyTokenAddr, sellAmount)
  .then(quote => console.log("\nQuote:", quote))
  .catch(err => console.error("Error getting quote:", err));
require('dotenv').config();
const ethers = require('ethers');

/**
 * Get a quote from 0x-API to sell the WETH we just deposited into the contract.
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

  // let decimals = 18;
  // if (!sellETH) decimals = await sellToken.decimals();
  // amt = ethers.utils.parseEther(amt, decimals);
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
  return quote;
};

const createQueryString = params => {
  return Object.entries(params)
    .map(([k, v]) => `${k}=${v}`)
    .join("&");
};

const sellTokenAddr = process.argv[2]; // First argument
const buyTokenAddr = process.argv[3]; // Second argument
const sellAmount = process.argv[4]; // Third argument

// Now you can call your function with these arguments
getQuote(sellTokenAddr, buyTokenAddr, sellAmount)
  .then(quote => console.log("\nQuote:", quote))
  .catch(err => console.error("Error getting quote:", err));
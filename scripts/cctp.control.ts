import { abi } from "../artifacts/contracts/CCTPSwap.sol/CCTPSwap.json";
import { ethers, Wallet } from "ethers";
import fs from "fs";

async function main() {
  const provider = new ethers.JsonRpcProvider(
    "https://opt-mainnet.g.alchemy.com/v2/QKCYUendor_IXnPdV3A451oKVKk9K6_6"
  );
  const signer = new Wallet(process.env.PRIVATE_KEY as string, provider);
  const CCTPContract = new ethers.Contract(
    "0x0b4756E69d8099287b3C3bd34C884f5f677E1878",
    abi,
    signer
  );
  const txHash = await CCTPContract.setExecutor(
    "0xd3B130ad6Fed9276E1fd486bCa4B9a428E670d6c"
  );
  console.log("txHash: ", txHash);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

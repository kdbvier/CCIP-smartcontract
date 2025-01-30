import { ethers, network } from "hardhat";
import fs from "fs";

async function main() {
  const [signer] = await ethers.getSigners();
  console.log("deployer: ", signer.address);
  const networkName = network.name;
  const config: Record<string, string[]> = {
    mainnet: [
      "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
      signer.address,
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      "0x0a992d191deec32afe36203ad87d7d289a738f81",
      "0xbd3fa81b58ba92a82136038b25adec7066af3155",
    ],
    avalanche: [
      "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7",
      signer.address,
      "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E",
      "0x8186359af5f57fbb40c6b14a588d2a59c0c29880",
      "0x6b25532e1060ce10cc3b0a99e5683b91bfde6982",
    ],
    base: [
      "0x4200000000000000000000000000000000000006",
      signer.address,
      "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
      "0xAD09780d193884d503182aD4588450C416D6F9D4",
      "0x1682Ae6375C4E4A97e4B583BC394c861A46D8962",
    ],
    arbitrumOne: [
      "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
      signer.address,
      "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
      "0xC30362313FBBA5cf9163F0bb16a0e01f01A896ca",
      "0x19330d10D9Cc8751218eaf51E8885D058642E08A",
    ],
    polygon: [
      "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
      signer.address,
      "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
      "0xF3be9355363857F3e001be68856A2f96b4C39Ba9",
      "0x9daF8c91AEFAE50b9c0E69629D3F6Ca40cA3B3FE"
    ],
    optimism: [
      "0x4200000000000000000000000000000000000006",
      signer.address,
      "0x0b2c639c533813f4aa9d7837caf62653d097ff85",
      "0x4d41f22c5a0e5c74090899e5a8fb597a8842b3e8",
      "0x2B4069517957735bE00ceE0fadAE88a26365528f"
    ],
  };
  console.log("deploying cctp contracts.......................");

  console.log("deploying on", networkName);
  // const CCTPDeployer = await ethers.getContractFactory(
  //   "CCTPSwap"
  // );
  // const CCTPContract = await CCTPDeployer.deploy(
  //   config[networkName][0],
  //   config[networkName][1],
  //   config[networkName][2],
  //   config[networkName][3],
  //   config[networkName][4],
  // );
  // const cctpContractAddress = await CCTPContract.getAddress();
  const cctpContractAddress = "0x096261Cc52fA5aE6151C7aD7883148eb75176b72";
  console.log(
    "cctpContractAddress on ",
    networkName,
    " : ",
    cctpContractAddress
  );
  console.log("verify waiting");
  await new Promise((resolve) => setTimeout(resolve, 3000));
  console.log("verify started");
  // @ts-ignore
  await run("verify:verify", {
    address: cctpContractAddress,
    constructorArguments: config[networkName],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

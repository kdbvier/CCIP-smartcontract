import { ethers, network } from "hardhat";
import fs from "fs";

async function main() {
  const [signer] = await ethers.getSigners();
  console.log("deployer: ", signer.address);
  const networkName = network.name;
  const config: Record<string, string[]> = {
    mainnet: [
      "0xd3B130ad6Fed9276E1fd486bCa4B9a428E670d6c",
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    ],
    avalanche: [
      "0xd3B130ad6Fed9276E1fd486bCa4B9a428E670d6c",
      "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E",
      "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7",
    ],
    base: [
      "0xd3B130ad6Fed9276E1fd486bCa4B9a428E670d6c",
      "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
      "0x4200000000000000000000000000000000000006",
    ],
    arbitrumOne: [
      "0xd3B130ad6Fed9276E1fd486bCa4B9a428E670d6c",
      "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
      "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
    ],
    polygon: [
      "0xd3B130ad6Fed9276E1fd486bCa4B9a428E670d6c",
      "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
      "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
    ],
    optimism: [
      "0xd3B130ad6Fed9276E1fd486bCa4B9a428E670d6c",
      "0x0b2c639c533813f4aa9d7837caf62653d097ff85",
      "0x4200000000000000000000000000000000000006",
    ],
  };
  console.log("deploying cctp contracts.......................");

  console.log("deploying on", networkName);
  const InstantDeployer = await ethers.getContractFactory(
    "OfficialInstantSwap"
  );
  const InstantContract = await InstantDeployer.deploy(
    config[networkName][0],
    config[networkName][1],
    config[networkName][2]
  );
  const instantContractAddress = await InstantContract.getAddress();
  console.log(
    "instantContractAddress on ",
    networkName,
    " : ",
    instantContractAddress
  );
  // console.log("verify waiting");
  // await new Promise((resolve) => setTimeout(resolve, 3000));
  // console.log("verify started");
  // // @ts-ignore
  // await run("verify:verify", {
  //   address: instantContractAddress,
  //   constructorArguments: config[networkName],
  // });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

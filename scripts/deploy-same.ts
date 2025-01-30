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
      "100",
    ],
    avalanche: [
      "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7",
      signer.address,
      "100"
    ],
    base: [
      "0x4200000000000000000000000000000000000006",
      signer.address,
      "100",
    ],
    arbitrumOne: [
      "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
      signer.address,
      "500",
    ],
    polygon: [
      "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
      signer.address,
      "100",
    ],
    optimism: [
      "0x4200000000000000000000000000000000000006",
      signer.address,
      "100",
    ],
  };
  console.log("deploying cswap router contracts.......................");

  console.log("deploying on", networkName);
    const SameswapDeployer = await ethers.getContractFactory("CSWAPSmartRouter");
    const SameswapContract = await SameswapDeployer.deploy(
      config[networkName][0],
      config[networkName][1],
      config[networkName][2],
    );
    const sameswapContractAddress = await SameswapContract.getAddress();
    console.log(
      "sameswapContractAddress on ",
      networkName,
      " : ",
      sameswapContractAddress
    );
  console.log('verify waiting')
  await new Promise((resolve) => setTimeout(resolve, 3000));
  console.log('verify started')
  // @ts-ignore
  await run("verify:verify", {
    address: sameswapContractAddress,
    constructorArguments: config[networkName],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

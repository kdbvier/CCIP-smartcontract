import { ethers, network } from "hardhat";
import fs from "fs";

async function main() {
  const [signer] = await ethers.getSigners();
  console.log("deployer: ", signer.address);
  const networkName = network.name;
  const config: Record<string, string[]> = {
    mainnet: [
      "0x6A000F20005980200259B80c5102003040001068",
      "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
      "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
      "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
      "500",
      "0xe1Ff5a4C489B11E094BFBB5d23c6d4597a3a79AD",
    ],
    avalanche: [
      "0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30",
      "0xd76019A16606FDa4651f636D9751f500Ed776250",
      "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E",
      signer.address,
    ],
    base: [
      "0x881e3A65B4d4a04dD529061dd0071cf975F58bCD",
      "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
      "0x2626664c2603336E57B271c5C0b26F421741e481",
      "0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24",
      "500",
      "0xe1Ff5a4C489B11E094BFBB5d23c6d4597a3a79AD",
      signer.address,
      "0x6A000F20005980200259B80c5102003040001068"
    ],
    arbitrumOne: [
      "0x141fa059441E0ca23ce184B6A78bafD2A517DdE8",
      "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
      "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
      "0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24",
      "500",
      "0xe1Ff5a4C489B11E094BFBB5d23c6d4597a3a79AD",
      signer.address,
      "0x6A000F20005980200259B80c5102003040001068"
    ],
    polygon: [
      "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
      "0xedf6066a2b290C185783862C7F4776A2C8077AD1",
      signer.address,
      "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
      "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
    ],
    optimism: [
      "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
      "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
      signer.address,
      "0x0b2c639c533813f4aa9d7837caf62653d097ff85",
      "0x4200000000000000000000000000000000000006",
    ],
  };
  console.log("deploying cctp contracts.......................");

  console.log("deploying on", networkName);
    const ParaDeployer = await ethers.getContractFactory("ParaCCIP");
    const ParaContract = await ParaDeployer.deploy(
      config[networkName][0],
      config[networkName][1],
      config[networkName][2],
      config[networkName][3],
      config[networkName][4],
      config[networkName][5],
      config[networkName][6],
      config[networkName][7],
    );
    const paraContractAddress = await ParaContract.getAddress();
    console.log(
      "paraContractAddress on ",
      networkName,
      " : ",
      paraContractAddress
    );
  console.log('verify waiting')
  await new Promise((resolve) => setTimeout(resolve, 3000));
  console.log('verify started')
  // @ts-ignore
  await run("verify:verify", {
    address: paraContractAddress,
    constructorArguments: config[networkName],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

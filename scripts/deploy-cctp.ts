import { ethers, network } from "hardhat";
import fs from "fs";



async function main() {
  const [signer] = await ethers.getSigners();
  console.log("deployer: ", signer.address);
  const networkName = network.name;
  const config:Record<string, string[]> = {
    mainnet: [
      "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
      "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
      signer.address,
      "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    ],
    avalanche: [
      "0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30",
      "0xd76019A16606FDa4651f636D9751f500Ed776250",
      "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E",
      signer.address,
    ],
    base: [
      "0x2626664c2603336e57b271c5c0b26f421741e481",
      "0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24",
      signer.address,
      "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
      "0x4200000000000000000000000000000000000006"
    ],
    arbitrumOne: [
      "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
      "0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24",
      signer.address,
      "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
      "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
      "0xC30362313FBBA5cf9163F0bb16a0e01f01A896ca",
      "0x19330d10D9Cc8751218eaf51E8885D058642E08A"
    ],
    polygon: [
      "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
      "0xedf6066a2b290C185783862C7F4776A2C8077AD1",
      signer.address,
      "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
      "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270"
    ],
    optimism: [
      "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45",
      "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
      signer.address,
      "0x0b2c639c533813f4aa9d7837caf62653d097ff85",
      "0x4200000000000000000000000000000000000006"
    ]
  }
  console.log('deploying cctp contracts.......................')
  if (networkName == "avalanche") {
    const InstantDeployer = await ethers.getContractFactory(
      "AvaxInstantSwap"
    );
    const InstantContract = await InstantDeployer.deploy(
      "0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30",
      "0xd76019A16606FDa4651f636D9751f500Ed776250",
      "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E",
      signer.address,
    );
    const instantContractAddress = await InstantContract.getAddress();
    console.log(
      "intstantContractAddress on ",
      networkName,
      " : ",
      instantContractAddress
    );
        // @ts-ignore
    await run("verify:verify", {
      address: instantContractAddress,
      constructorArguments: config.avalanche,
    });
  } else {
    console.log('deploying on', networkName)
    const CCTPDeployer = await ethers.getContractFactory(
      "CCTPSwap"
    );
    const CCTPContract = await CCTPDeployer.deploy(
      config[networkName][0],
      config[networkName][1],
      config[networkName][2],
      config[networkName][3],
      config[networkName][4],
      config[networkName][5],
      config[networkName][6]
    );
    const cctpContractAddress = await CCTPContract.getAddress();
    console.log(
      "cctpContractAddress on ",
      networkName,
      " : ",
      cctpContractAddress
    );
    // @ts-ignore
    // await run("verify:verify", {
    //   address: "0x41C8508A42A9e383DdcA8964Efee7c08dFE64647",
    //   constructorArguments: config[networkName],
    // });
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

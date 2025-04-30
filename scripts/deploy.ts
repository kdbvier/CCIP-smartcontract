import { ethers, network } from "hardhat";

async function main() {
  const [signer] = await ethers.getSigners();
  console.log("deployer: ", signer.address);
  const networkName = network.name;
  const ERC20Deployer = await ethers.getContractFactory("BatchTransfer");
  const ERC20Contract = await ERC20Deployer.deploy();
  const address = await ERC20Contract.getAddress();
  console.log(
    "intstantContractAddress on ",
    networkName,
    " : ",
    address
  );
  // @ts-ignore
  await run("verify:verify", {
    address: "0x0D307FFf31CFbAA515f3843b70f3336E69F489B2",
    constructorArguments: [],
  });
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

import { ethers, network } from "hardhat";

const contractAddresses: Record<string, string> = {
  base: "0x9399a6e310b39E19950Da67e3cCb8F227875F3CD",
  arbitrumOne: "0xbdD423431aad35477eDe9e052fe60c1B5B0BebD5",
};
const chains = [
  "5009297550715157269",
  "3734403246176062136",
  "4949039107694359620",
  "4051577828743386545",
  "6433500567565415381",
  "15971525489660198786",
];
async function main() {
  const [signer] = await ethers.getSigners();
  console.log("deployer: ", signer.address);
  const networkName = network.name;
  const contract = await ethers.getContractAt(
    "ParaCCIP",
    contractAddresses[networkName],
    signer
  );
    for (let i = 0; i < chains.length; i++) {
      const tx1 = await contract.allowlistDestinationChain(chains[i], true);
      await tx1.wait();
      console.log('dest',chains[i])
      const tx2 = await contract.allowlistSourceChain(chains[i], true);
      await tx2.wait();
      console.log('source',chains[i])
    }
  // for (let i = 0; i < 2; i++) {
  //   const contractAddress2 = Object.values(contractAddresses)[i];
  //   console.log("-- Allowing sender", contractAddress2);
  //   const tx = await contract.allowlistSender(contractAddress2, true);
  //   await tx.wait();
  // }
}

main();

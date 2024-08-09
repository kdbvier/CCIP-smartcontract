import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
require('dotenv').config()
const PRIVATE_KEY = process.env.PRIVATE_KEY || ""

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 100,
      },
      viaIR: true,
    },
  },
  networks: {
    mainnet: {
      url: "https://ethereum.chain-swap.org",
      accounts: [PRIVATE_KEY],
    },
    avalanche: {
      url: "https://avax.chain-swap.org/rpc",
      accounts: [PRIVATE_KEY],
    },
    base: {
      url: "https://base.chain-swap.org",
      accounts: [PRIVATE_KEY],
    },
    arbitrumOne: {
      url: "https://arbitrum.chain-swap.org",
      accounts: [PRIVATE_KEY],
    },
    polygon: {
      url: "https://polygon.chain-swap.org",
      accounts: [PRIVATE_KEY],
    },
    optimism: {
      url: "https://optimism.chain-swap.org",
      accounts: [PRIVATE_KEY],
    }
  },
  etherscan: {
    apiKey: {
      mainnet: "636XAI7HYPRIVQHKM14UVPBP3TKM3B27TC",
      avalanche: "snowtrace",
      base: "N6IYXG16H3VFXXVMJC65TS9USEKEAJ3WWP",
      arbitrumOne: "9M8FKJCURK1JM6FYHFZXPDS9AUIV1E41RA",
      polygon: "SZH5914WVZXFIHIX3STNRF6ACCZCISAHGS",
      optimisticEthereum: "II8VACAZQFIK96UJGFI3ATID3TFMFBRHC2"
    }
  }
};

export default config;

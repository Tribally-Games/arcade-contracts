require('dotenv').config()

const SALT = "0xf12ac9c61a8571f3e439a5639165f9fca467e2f6de7086f2b4076c0a194d1949"

module.exports = {
  version: 2,
  solc: {
    license: "MIT",
    version: "0.8.24",
  },
  commands: {
    build: "forge build --names --sizes",
  },
  paths: {
    artifacts: "out",
    src: {
      facets: [
        "src/facets/*Facet.sol",
      ],
    },
    generated: {
      solidity: "src/generated",
      support: ".gemforge",
      deployments: "gemforge.deployments.json",
    },
    lib: {
      diamond: "lib/diamond-2-hardhat",
    },
  },
  artifacts: {
    format: "foundry",
  },
  generator: {
    proxyInterface: {
      imports: ["src/shared/Structs.sol"],
    },
  },
  diamond: {
    publicMethods: false,
    init: {
      contract: "InitDiamond",
      function: "init",
    },
    coreFacets: ["OwnershipFacet", "DiamondCutFacet", "DiamondLoupeFacet"],
    protectedMethods: [
      '0x8da5cb5b',
      '0xf2fde38b',
      '0x1f931c1c',
      '0x7a0ed627',
      '0xcdffacc6',
      '0x52ef6b2c',
      '0xadfca15e',
      '0x01ffc9a7',
    ],
  },
  hooks: {
    preBuild: "",
    postBuild: "",
    preDeploy: "./scripts/pre-deploy.ts",
    postDeploy: "./scripts/post-deploy.ts",
  },
  wallets: {
    local_wallet: {
      type: "mnemonic",
      config: {
        words: "test test test test test test test test test test test junk",
        index: 0,
      },
    },
    deployer_wallet: {
      type: "private-key",
      config: {
        key: process.env.DEPLOYER_PRIVATE_KEY || '',
      },
    },
  },
  networks: {
    devnet1: {
      rpcUrl: "http://localhost:8545",
    },
    devnet2: {
      rpcUrl: "http://localhost:8546",
    },
    base: {
      rpcUrl: "https://base.lava.build",
      contractVerification: {
        foundry: {
          apiUrl: "https://api.etherscan.io/v2/api?chainid=8453",
          apiKey: process.env.ETHERSCAN_API_KEY || '',
        },
      },
    },
    baseFork: {
      rpcUrl: 'http://localhost:8545/',
    },
    ronin: {
      rpcUrl: "https://api.roninchain.com/rpc",
      contractVerification: {
        foundry: {
          apiUrl: "https://sourcify.roninchain.com/server/",
          chainId: 2020,
          verifier: 'sourcify',
        },
      },
    }
  },
  targets: {
    devnet1: {
      network: "devnet1",
      wallet: "local_wallet",
      initArgs: [
        "0x7fB0e77f4B958FCdEE59564E4e6526EAB2002141",
        "0x302916C3a7Fe06B120b92d91A07A92180fa18625",
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
      ],
      create3Salt: SALT,
    },
    devnet2: {
      network: "devnet2",
      wallet: "local_wallet",
      initArgs: [
        "0x7fB0e77f4B958FCdEE59564E4e6526EAB2002141",
        "0x302916C3a7Fe06B120b92d91A07A92180fa18625",
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
      ],
      create3Salt: SALT,
    },
    base: {
      network: "base",
      wallet: "deployer_wallet",
      initArgs: [
        "0xe13E40e8FdB815FBc4a1E2133AB5588C33BaC45d",
        "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
        "0x000000000000000000000000000000000000dead"
      ],
      create3Salt: SALT,
      upgrades: {
        manualCut: true
      }
    },
    ronin: {
      network: "ronin",
      wallet: "deployer_wallet",
      initArgs: [
        "0xe13E40e8FdB815FBc4a1E2133AB5588C33BaC45d",
        "0x0b7007c13325c48911f73a2dad5fa5dcbf808adc",
        "0x000000000000000000000000000000000000dead"
      ],
      create3Salt: SALT,
      upgrades: {
        manualCut: true
      }
    },
    baseFork: {
      network: 'baseFork',
      wallet: 'local_wallet',
      initArgs: [],
      upgrades: {
        manualCut: true
      }
    },
  },
};

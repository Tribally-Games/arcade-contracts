require('dotenv').config()

const SALT_MAINNET = "0xf93ac9c61a8577e3e439a5639f65f9eca367e2c6de7086f3b4076c0a895d1919"
const SALT_TESTNET = "0xf93ac9c61a8577e3e439a5639f65f9eca367e2c6de7086f3b4076c0a895d1919"

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
    preDeploy: "",
    postDeploy: "",
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
        key: process.env.DEPLOYER_PRIVATE_KEY
      },
    },
  },
  networks: {
    local: {
      rpcUrl: "http://localhost:8545",
    },
    base_sepolia: {
      rpcUrl: "https://sepolia.base.org",
      contractVerification: {
        foundry: {
          apiUrl: "https://api-sepolia.basescan.org/api",
          apiKey: process.env.BASESCAN_API_KEY,
        },
      },
    },
    base: {
      rpcUrl: "https://base.lava.build",
      contractVerification: {
        foundry: {
          apiUrl: "https://api.basescan.org/api",
          apiKey: process.env.BASESCAN_API_KEY,
        },
      },
    },
    baseFork: {
      rpcUrl: 'http://localhost:8545/',
    }
  },
  targets: {
    local: {
      network: "local",
      wallet: "local_wallet",
      initArgs: [
        "0x000000000000000000000000000000000000dead",
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
      ],
      create3Salt: SALT_TESTNET,
    },
    base_sepolia: {
      network: "base_sepolia",
      wallet: "deployer_wallet",
      initArgs: [
        "0xe13E40e8FdB815FBc4a1E2133AB5588C33BaC45d",
        "0x000000000000000000000000000000000000dead"
      ],
      create3Salt: SALT_TESTNET,
    },
    base: {
      network: "base",
      wallet: "deployer_wallet",
      initArgs: [
        "0xe13E40e8FdB815FBc4a1E2133AB5588C33BaC45d",
        "0x000000000000000000000000000000000000dead"
      ],
      create3Salt: SALT_MAINNET,
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
    }
  },
};

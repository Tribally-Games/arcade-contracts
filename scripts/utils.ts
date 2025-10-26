import { createPublicClient, createWalletClient, http, type Chain, type Account } from 'viem';
import { mnemonicToAccount } from 'viem/accounts';
import { privateKeyToAccount } from 'viem/accounts';
import { foundry, base } from 'viem/chains';
import { readFileSync } from 'fs';
import { join } from 'path';

function createRoninChain(rpcUrl: string): Chain {
  return {
    id: 2020,
    name: 'Ronin',
    nativeCurrency: {
      decimals: 18,
      name: 'RON',
      symbol: 'RON',
    },
    rpcUrls: {
      default: { http: [rpcUrl] },
      public: { http: [rpcUrl] },
    },
    blockExplorers: {
      default: { name: 'Ronin Explorer', url: 'https://app.roninchain.com' },
    },
  };
}

function createLocal2Chain(rpcUrl: string): Chain {
  return {
    id: 31338,
    name: 'Local Devnet 2',
    nativeCurrency: {
      decimals: 18,
      name: 'Ether',
      symbol: 'ETH',
    },
    rpcUrls: {
      default: { http: [rpcUrl] },
      public: { http: [rpcUrl] },
    },
  };
}

export interface ClientSetup {
  publicClient: ReturnType<typeof createPublicClient>;
  walletClient: ReturnType<typeof createWalletClient>;
  account: Account;
}

export interface VerificationConfig {
  apiUrl: string;
  apiKey: string;
  chainId?: number;
  verifier?: string;
}

export interface GemforgeConfig {
  wallets: {
    [key: string]: {
      type: 'mnemonic' | 'private-key';
      config: any;
    };
  };
  networks: {
    [key: string]: {
      rpcUrl: string;
      contractVerification?: {
        foundry: {
          apiUrl: string;
          apiKey: string;
          chainId?: number;
          verifier?: string;
        };
      };
    };
  };
  targets: {
    [key: string]: {
      network: string;
      wallet: string;
    };
  };
}

export function loadGemforgeConfig(): GemforgeConfig {
  const configPath = join(process.cwd(), 'gemforge.config.cjs');
  return require(configPath);
}

export function getChainConfig(target: string, rpcUrl: string): Chain {
  switch (target) {
    case 'devnet1':
    case 'baseFork':
      return foundry;
    case 'devnet2':
      return createLocal2Chain(rpcUrl);
    case 'base':
      return base;
    case 'ronin':
      return createRoninChain(rpcUrl);
    default:
      throw new Error(`Unknown target: ${target}`);
  }
}

export function getRpcUrl(target: string, configRpcUrl?: string): string {
  if (configRpcUrl) {
    return configRpcUrl;
  }

  const config = loadGemforgeConfig();
  const targetConfig = config.targets[target];

  if (!targetConfig) {
    throw new Error(`Target ${target} not found in gemforge config`);
  }

  const networkName = targetConfig.network;
  const networkConfig = config.networks[networkName];

  if (!networkConfig) {
    throw new Error(`Network ${networkName} not found in gemforge config`);
  }

  return networkConfig.rpcUrl;
}

export function loadWallet(target: string): Account {
  const config = loadGemforgeConfig();
  const targetConfig = config.targets[target];

  if (!targetConfig) {
    throw new Error(`Target ${target} not found in gemforge config`);
  }

  const walletName = targetConfig.wallet;
  const walletConfig = config.wallets[walletName];

  if (!walletConfig) {
    throw new Error(`Wallet ${walletName} not found in gemforge config`);
  }

  if (walletConfig.type === 'mnemonic') {
    return mnemonicToAccount(walletConfig.config.words, {
      addressIndex: walletConfig.config.index,
    });
  } else if (walletConfig.type === 'private-key') {
    if (!walletConfig.config.key) {
      throw new Error(`Private key not configured for wallet ${walletName}`);
    }
    return privateKeyToAccount(walletConfig.config.key as `0x${string}`);
  } else {
    throw new Error(`Unsupported wallet type: ${walletConfig.type}`);
  }
}

export function createClients(target: string, rpcUrl?: string): ClientSetup {
  const finalRpcUrl = getRpcUrl(target, rpcUrl);
  const chain = getChainConfig(target, finalRpcUrl);
  const account = loadWallet(target);

  const publicClient = createPublicClient({
    chain,
    transport: http(finalRpcUrl),
  });

  const walletClient = createWalletClient({
    account,
    chain,
    transport: http(finalRpcUrl),
  });

  return { publicClient, walletClient, account };
}

export function getVerificationConfig(target: string): VerificationConfig | null {
  const config = loadGemforgeConfig();
  const targetConfig = config.targets[target];

  if (!targetConfig) {
    return null;
  }

  const networkName = targetConfig.network;
  const networkConfig = config.networks[networkName];

  if (!networkConfig?.contractVerification?.foundry) {
    return null;
  }

  const verification = networkConfig.contractVerification.foundry;

  if (!verification.apiUrl) {
    return null;
  }

  return {
    apiUrl: verification.apiUrl,
    apiKey: verification.apiKey || '',
    chainId: verification.chainId,
    verifier: verification.verifier,
  };
}

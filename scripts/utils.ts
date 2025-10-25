import { createPublicClient, createWalletClient, http, type Chain, type Account } from 'viem';
import { mnemonicToAccount } from 'viem/accounts';
import { privateKeyToAccount } from 'viem/accounts';
import { foundry, base } from 'viem/chains';
import { readFileSync } from 'fs';
import { join } from 'path';

const ronin: Chain = {
  id: 2020,
  name: 'Ronin',
  nativeCurrency: {
    decimals: 18,
    name: 'RON',
    symbol: 'RON',
  },
  rpcUrls: {
    default: { http: ['https://api.roninchain.com/rpc'] },
    public: { http: ['https://api.roninchain.com/rpc'] },
  },
  blockExplorers: {
    default: { name: 'Ronin Explorer', url: 'https://app.roninchain.com' },
  },
};

export interface ClientSetup {
  publicClient: ReturnType<typeof createPublicClient>;
  walletClient: ReturnType<typeof createWalletClient>;
  account: Account;
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

export function getChainConfig(target: string): Chain {
  switch (target) {
    case 'local':
    case 'baseFork':
      return foundry;
    case 'base':
      return base;
    case 'ronin':
      return ronin;
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
  const chain = getChainConfig(target);
  const finalRpcUrl = getRpcUrl(target, rpcUrl);
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

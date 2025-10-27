import { encodePacked } from 'viem';
import DIAMOND_ABI from '../src/generated/abi.json';
import IDexSwapAdapterArtifact from '../out/IDexSwapAdapter.sol/IDexSwapAdapter.json';

export { DIAMOND_ABI };

export const ADAPTER_ABI = IDexSwapAdapterArtifact.abi;

export type TokenConfig = {
  address: `0x${string}`;
  symbol: string;
  decimals: number;
};

export type NetworkTokens = {
  [key: string]: TokenConfig;
};

export type NetworkConfig = {
  wethAddress: `0x${string}`;
  usdcAddress: `0x${string}`;
  feeTier: number;
  nativeSymbol: string;
  wrappedSymbol: string;
};

export const TOKEN_CONFIGS: Record<string, NetworkTokens> = {
  ronin: {
    ron: {
      address: '0x0000000000000000000000000000000000000000',
      symbol: 'RON',
      decimals: 18,
    },
    wron: {
      address: '0xe514d9deb7966c8be0ca922de8a064264ea6bcd4',
      symbol: 'WRON',
      decimals: 18,
    },
    usdc: {
      address: '0x0b7007c13325c48911f73a2dad5fa5dcbf808adc',
      symbol: 'USDC',
      decimals: 6,
    },
  },
  base: {
    eth: {
      address: '0x0000000000000000000000000000000000000000',
      symbol: 'ETH',
      decimals: 18,
    },
    weth: {
      address: '0x4200000000000000000000000000000000000006',
      symbol: 'WETH',
      decimals: 18,
    },
    usdc: {
      address: '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913',
      symbol: 'USDC',
      decimals: 6,
    },
  },
  devnet1: {
    eth: {
      address: '0x0000000000000000000000000000000000000000',
      symbol: 'ETH',
      decimals: 18,
    },
    weth: {
      address: '0x662113AF572d65cB6FBC144F1ECeF4EB6e7c608C',
      symbol: 'WETH',
      decimals: 18,
    },
    usdc: {
      address: '0x302916C3a7Fe06B120b92d91A07A92180fa18625',
      symbol: 'USDC',
      decimals: 6,
    },
    tribal: {
      address: '0x7fB0e77f4B958FCdEE59564E4e6526EAB2002141',
      symbol: 'TRIBAL',
      decimals: 18,
    },
  },
  devnet2: {
    eth: {
      address: '0x0000000000000000000000000000000000000000',
      symbol: 'ETH',
      decimals: 18,
    },
    weth: {
      address: '0x662113AF572d65cB6FBC144F1ECeF4EB6e7c608C',
      symbol: 'WETH',
      decimals: 18,
    },
    usdc: {
      address: '0x302916C3a7Fe06B120b92d91A07A92180fa18625',
      symbol: 'USDC',
      decimals: 6,
    },
    tribal: {
      address: '0x7fB0e77f4B958FCdEE59564E4e6526EAB2002141',
      symbol: 'TRIBAL',
      decimals: 18,
    },
  },
};

export const DEX_ROUTERS: Record<string, { katana?: `0x${string}`; uniswap?: `0x${string}`; dummy?: `0x${string}` }> = {
  ronin: {
    katana: '0x5f0acdd3ec767514ff1bf7e79949640bf94576bd',
  },
  base: {
    uniswap: '0x6fF5693b99212Da76ad316178A184AB56D299b43',
  },
  devnet1: {
    dummy: '0x4cBac2f21c2c8bBeC82612Ed5FAc526DD211e991',
  },
  devnet2: {
    dummy: '0x4cBac2f21c2c8bBeC82612Ed5FAc526DD211e991',
  },
};

export const NETWORK_CONFIGS: Record<string, NetworkConfig> = {
  ronin: {
    wethAddress: '0xe514d9deb7966c8be0ca922de8a064264ea6bcd4',
    usdcAddress: '0x0b7007c13325c48911f73a2dad5fa5dcbf808adc',
    feeTier: 3000,
    nativeSymbol: 'RON',
    wrappedSymbol: 'WRON',
  },
  base: {
    wethAddress: '0x4200000000000000000000000000000000000006',
    usdcAddress: '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913',
    feeTier: 3000,
    nativeSymbol: 'ETH',
    wrappedSymbol: 'WETH',
  },
  local: {
    wethAddress: '0x662113AF572d65cB6FBC144F1ECeF4EB6e7c608C',
    usdcAddress: '0x302916C3a7Fe06B120b92d91A07A92180fa18625',
    feeTier: 3000,
    nativeSymbol: 'ETH',
    wrappedSymbol: 'WETH',
  },
};

export function getTokenConfig(network: string, tokenType: string): TokenConfig | null {
  const networkTokens = TOKEN_CONFIGS[network];
  if (!networkTokens) return null;
  return networkTokens[tokenType.toLowerCase()] || null;
}

export function buildSwapPath(
  tokenInAddress: `0x${string}`,
  tokenOutAddress: `0x${string}`,
  feeTier: number = 3000
): `0x${string}` {
  const wethAddress = tokenInAddress === '0x0000000000000000000000000000000000000000'
    ? (TOKEN_CONFIGS.ronin?.wron?.address || TOKEN_CONFIGS.base?.weth?.address)
    : tokenInAddress;

  return encodePacked(
    ['address', 'uint24', 'address'],
    [wethAddress as `0x${string}`, feeTier, tokenOutAddress]
  );
}

export function formatTokenAmount(amount: bigint, decimals: number, symbol?: string): string {
  const divisor = 10n ** BigInt(decimals);
  const whole = amount / divisor;
  const fraction = amount % divisor;
  const fractionStr = fraction.toString().padStart(decimals, '0');
  const formatted = `${whole}.${fractionStr.slice(0, Math.min(6, decimals))}`;
  return symbol ? `${formatted} ${symbol}` : formatted;
}

export function parseTokenAmount(amount: string, decimals: number): bigint {
  const [whole = '0', fraction = '0'] = amount.split('.');
  const paddedFraction = fraction.padEnd(decimals, '0').slice(0, decimals);
  return BigInt(whole) * (10n ** BigInt(decimals)) + BigInt(paddedFraction);
}

export function isNativeToken(address: string): boolean {
  return address === '0x0000000000000000000000000000000000000000' || address === '0x0';
}

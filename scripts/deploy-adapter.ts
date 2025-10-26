#!/usr/bin/env bun

import { Command } from 'commander';
import { createClients, type ClientSetup } from './utils';
import { DEX_ROUTERS, TOKEN_CONFIGS } from './gateway-utils';
import { type Hex } from 'viem';
import { deployWithCreate3, type DeployResult } from './create3-deploy';

const CREATE3_SALT = '0x4445585f4144415054455200000000000000000000000000000000000000beef' as Hex;

export async function deployAdapter(
  network: string,
  options: {
    router?: string;
    usdc?: string;
    weth?: string;
    owner?: string;
  } = {}
): Promise<DeployResult> {
  if (!['ronin', 'base', 'local1', 'local2'].includes(network)) {
    throw new Error(`Invalid network: ${network}. Valid networks: ronin, base, local1, local2`);
  }

  const adapterType =
    network === 'base' ? 'uniswap'
    : (network === 'local1' || network === 'local2') ? 'dummy'
    : 'katana';

  const clients = createClients(network);

  let contractName: string;
  let contractPath: string;
  let constructorArgs: any[];
  let constructorTypes: string[];

  if (adapterType === 'dummy') {
    const wethAddress = options.weth || TOKEN_CONFIGS[network]?.weth?.address;
    const usdcAddress = options.usdc || TOKEN_CONFIGS[network]?.usdc?.address;
    const ownerAddress = (options.owner || clients.account.address) as Hex;

    if (!wethAddress) {
      throw new Error(`No default WETH address for ${network}`);
    }
    if (!usdcAddress) {
      throw new Error(`No default USDC address for ${network}`);
    }

    contractName = 'DummyDexAdapter';
    contractPath = 'DummyDexAdapter.sol';
    constructorArgs = [wethAddress, usdcAddress, ownerAddress];
    constructorTypes = ['address', 'address', 'address'];
  } else {
    const routerAddress = options.router || DEX_ROUTERS[network]?.[adapterType as 'katana' | 'uniswap'];
    const usdcAddress = options.usdc || TOKEN_CONFIGS[network]?.usdc?.address;
    const ownerAddress = (options.owner || clients.account.address) as Hex;

    if (!routerAddress) {
      throw new Error(`No default router address for ${adapterType} on ${network}`);
    }
    if (!usdcAddress) {
      throw new Error(`No default USDC address for ${network}`);
    }

    contractName = adapterType === 'katana' ? 'KatanaSwapAdapter' : 'UniswapV3SwapAdapter';
    contractPath = `${contractName}.sol`;
    constructorArgs = [routerAddress, usdcAddress, ownerAddress];
    constructorTypes = ['address', 'address', 'address'];
  }

  const result = await deployWithCreate3(clients, {
    contractName,
    contractPath,
    constructorArgs,
    constructorTypes,
    salt: CREATE3_SALT,
  });

  return result;
}

async function main() {
  const program = new Command();

  program
    .name('deploy-adapter')
    .description('Deploy a DEX swap adapter contract using CREATE3')
    .argument('<network>', 'Network to deploy to (ronin|base|local1|local2)')
    .option('--router <address>', 'DEX router address (optional, uses defaults)')
    .option('--usdc <address>', 'USDC token address (optional, uses defaults)')
    .option('--weth <address>', 'WETH token address (optional, uses defaults, for local networks)')
    .option('--owner <address>', 'Adapter owner (optional, uses deployer)')
    .parse();

  const [network] = program.args;
  const options = program.opts();

  const adapterType =
    network === 'base' ? 'uniswap'
    : (network === 'local1' || network === 'local2') ? 'dummy'
    : 'katana';
  const clients = createClients(network);

  let routerOrWethAddress: string | undefined;
  if (adapterType === 'dummy') {
    routerOrWethAddress = options.weth || TOKEN_CONFIGS[network]?.weth?.address;
  } else {
    routerOrWethAddress = options.router || DEX_ROUTERS[network]?.[adapterType as 'katana' | 'uniswap'];
  }

  const usdcAddress = options.usdc || TOKEN_CONFIGS[network]?.usdc?.address;
  const ownerAddress = options.owner || clients.account.address;

  console.log('╔════════════════════════════════════════╗');
  console.log('║       Deploy DEX Adapter               ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Network:     ${network.toUpperCase()}`);
  console.log(`Adapter:     ${adapterType.toUpperCase()}`);
  if (adapterType === 'dummy') {
    console.log(`WETH:        ${routerOrWethAddress}`);
  } else {
    console.log(`Router:      ${routerOrWethAddress}`);
  }
  console.log(`USDC:        ${usdcAddress}`);
  console.log(`Owner:       ${ownerAddress}`);
  console.log(`Deployer:    ${clients.account.address}`);
  console.log(`Salt:        ${CREATE3_SALT}`);
  console.log('─────────────────────────────────────────\n');

  console.log('🚀 Deploying adapter with CREATE3...\n');

  const result = await deployAdapter(network, options);

  if (result.alreadyDeployed) {
    console.log('╔════════════════════════════════════════╗');
    console.log('║      Already Deployed                  ║');
    console.log('╚════════════════════════════════════════╝');
    console.log(`Adapter Address: ${result.address}`);
    console.log('\n✅ Adapter already deployed at this address!');
  } else {
    console.log('╔════════════════════════════════════════╗');
    console.log('║         Deployment Success             ║');
    console.log('╚════════════════════════════════════════╝');
    console.log(`Adapter Address: ${result.address}`);
    console.log(`Transaction:     ${result.txHash}`);
    console.log(`Gas Used:        ${result.gasUsed}`);
    console.log('\n✅ Adapter deployed successfully!');
  }
}

main().catch((error) => {
  console.error('\n❌ Deployment failed:', error.message);
  process.exit(1);
});

#!/usr/bin/env bun

import { Command } from 'commander';
import { createClients, getVerificationConfig } from './utils';
import { DEX_ROUTERS, TOKEN_CONFIGS } from './gateway-utils';
import { type Hex } from 'viem';
import { deployWithCreate3, type DeployResult } from './create3-deploy';

const CREATE3_SALT = '0x4445585f41444150544552000000000000000000000000000000000000001aff' as Hex;

const QUOTER_V2_ADDRESSES: Record<string, string> = {
  base: '0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a',
};

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

    if (!wethAddress) {
      throw new Error(`No default WETH address for ${network}`);
    }
    if (!usdcAddress) {
      throw new Error(`No default USDC address for ${network}`);
    }

    contractName = 'DummyDexAdapter';
    contractPath = 'DummyDexAdapter.sol';
    constructorArgs = [wethAddress, usdcAddress];
    constructorTypes = ['address', 'address'];
  } else if (adapterType === 'katana') {
    const routerAddress = options.router || DEX_ROUTERS[network]?.katana;

    if (!routerAddress) {
      throw new Error(`No default router address for katana on ${network}`);
    }

    contractName = 'KatanaSwapAdapter';
    contractPath = `${contractName}.sol`;
    constructorArgs = [routerAddress];
    constructorTypes = ['address'];
  } else {
    // uniswap
    const routerAddress = options.router || DEX_ROUTERS[network]?.uniswap;
    const quoterAddress = QUOTER_V2_ADDRESSES[network];

    if (!routerAddress) {
      throw new Error(`No default router address for uniswap on ${network}`);
    }
    if (!quoterAddress) {
      throw new Error(`No QuoterV2 address configured for ${network}`);
    }

    contractName = 'UniswapV3SwapAdapter';
    contractPath = `${contractName}.sol`;
    constructorArgs = [routerAddress, quoterAddress];
    constructorTypes = ['address', 'address'];
  }

  const verification = getVerificationConfig(network);

  const result = await deployWithCreate3(clients, {
    contractName,
    contractPath,
    constructorArgs,
    constructorTypes,
    salt: CREATE3_SALT,
    verification: verification ?? undefined,
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
    .option('--usdc <address>', 'USDC token address (optional, uses defaults, for dummy adapter only)')
    .option('--weth <address>', 'WETH token address (optional, uses defaults, for dummy adapter only)')
    .parse();

  const [network] = program.args;
  const options = program.opts();

  const adapterType =
    network === 'base' ? 'uniswap'
    : (network === 'local1' || network === 'local2') ? 'dummy'
    : 'katana';
  const clients = createClients(network);

  console.log('╔════════════════════════════════════════╗');
  console.log('║       Deploy DEX Adapter               ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Network:     ${network.toUpperCase()}`);
  console.log(`Adapter:     ${adapterType.toUpperCase()}`);

  if (adapterType === 'dummy') {
    const wethAddress = options.weth || TOKEN_CONFIGS[network]?.weth?.address;
    const usdcAddress = options.usdc || TOKEN_CONFIGS[network]?.usdc?.address;
    console.log(`WETH:        ${wethAddress}`);
    console.log(`USDC:        ${usdcAddress}`);
  } else if (adapterType === 'uniswap') {
    const routerAddress = options.router || DEX_ROUTERS[network]?.uniswap;
    const quoterAddress = QUOTER_V2_ADDRESSES[network];
    console.log(`Router:      ${routerAddress}`);
    console.log(`QuoterV2:    ${quoterAddress}`);
  } else {
    const routerAddress = options.router || DEX_ROUTERS[network]?.katana;
    console.log(`Router:      ${routerAddress}`);
  }

  console.log(`Owner:       ${clients.account.address} (deployer)`);
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

  if (result.verified) {
    console.log('✅ Contract verified on block explorer!');
  } else if (result.verificationError) {
    console.log(`⚠️  Verification failed: ${result.verificationError}`);
  }
}

main().catch((error) => {
  console.error('\n❌ Deployment failed:', error.message);
  process.exit(1);
});

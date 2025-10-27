#!/usr/bin/env bun

import { Command } from 'commander';
import { createClients, getVerificationConfig } from './utils';
import { DEX_ROUTERS, TOKEN_CONFIGS } from './gateway-utils';
import { type Hex } from 'viem';
import { deployWithCreate3, type DeployResult } from './create3-deploy';

const CREATE3_SALT = '0x4445585f41444150544552000000000000000000000000000000000000013aff' as Hex;

export async function deployAdapter(
  network: string,
  options: {
    router?: string;
    usdc?: string;
    weth?: string;
    owner?: string;
    skipVerification?: boolean;
  } = {}
): Promise<DeployResult> {
  if (!['ronin', 'base', 'devnet1', 'devnet2'].includes(network)) {
    throw new Error(`Invalid network: ${network}. Valid networks: ronin, base, devnet1, devnet2`);
  }

  const adapterType =
    (network === 'devnet1' || network === 'devnet2') ? 'dummy'
    : 'universal';

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
  } else {
    // Universal adapter works with both Katana (Ronin) and Uniswap (Base) routers
    const routerAddress = options.router ||
      (network === 'base' ? DEX_ROUTERS[network]?.uniswap : DEX_ROUTERS[network]?.katana);

    if (!routerAddress) {
      throw new Error(`No default router address for ${network}`);
    }

    contractName = 'UniversalSwapAdapter';
    contractPath = `${contractName}.sol`;
    constructorArgs = [routerAddress];
    constructorTypes = ['address'];
  }

  const verification = options.skipVerification ? undefined : getVerificationConfig(network);

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
    .argument('<network>', 'Network to deploy to (ronin|base|devnet1|devnet2)')
    .option('--router <address>', 'DEX router address (optional, uses defaults)')
    .option('--usdc <address>', 'USDC token address (optional, uses defaults, for dummy adapter only)')
    .option('--weth <address>', 'WETH token address (optional, uses defaults, for dummy adapter only)')
    .parse();

  const [network] = program.args;
  const options = program.opts();

  const adapterType =
    (network === 'devnet1' || network === 'devnet2') ? 'dummy'
    : 'universal';
  const routerType = network === 'base' ? 'Uniswap' : 'Katana';
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
  } else {
    const routerAddress = options.router ||
      (network === 'base' ? DEX_ROUTERS[network]?.uniswap : DEX_ROUTERS[network]?.katana);
    console.log(`Router Type: ${routerType}`);
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

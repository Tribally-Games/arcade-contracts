#!/usr/bin/env bun

import { Command } from 'commander';
import { createClients, getVerificationConfig } from './utils';
import { DEX_ROUTERS, TOKEN_CONFIGS } from './gateway-utils';
import { type Hex } from 'viem';
import { deployWithCreate3, type DeployResult, verifyContract } from './create3-deploy';

const CREATE3_SALT = '0x4445585a21442151541152000000010000010000110000000010010200013bff' as Hex;

export async function deployDepositor(
  network: string,
  options: {
    diamond: string;
    router?: string;
    usdc?: string;
    weth?: string;
    owner?: string;
    skipVerification?: boolean;
  }
): Promise<DeployResult> {
  if (!['ronin', 'base', 'devnet1', 'devnet2'].includes(network)) {
    throw new Error(`Invalid network: ${network}. Valid networks: ronin, base, devnet1, devnet2`);
  }

  if (!options.diamond) {
    throw new Error('Diamond proxy address is required (--diamond option)');
  }

  const depositorType =
    (network === 'devnet1' || network === 'devnet2') ? 'dummy'
    : 'universal';

  const clients = createClients(network);

  let contractName: string;
  let contractPath: string;
  let constructorArgs: any[];
  let constructorTypes: string[];

  const usdcAddress = options.usdc || TOKEN_CONFIGS[network]?.usdc?.address;
  const ownerAddress = options.owner || clients.account.address;

  if (!usdcAddress) {
    throw new Error(`No default USDC address for ${network}`);
  }

  if (depositorType === 'dummy') {
    const wethAddress = options.weth || TOKEN_CONFIGS[network]?.weth?.address;

    if (!wethAddress) {
      throw new Error(`No default WETH address for ${network}`);
    }

    contractName = 'DummyDexDepositor';
    contractPath = 'DummyDexDepositor.sol';
    constructorArgs = [wethAddress, options.diamond, usdcAddress, ownerAddress];
    constructorTypes = ['address', 'address', 'address', 'address'];
  } else {
    const routerAddress = options.router ||
      (network === 'base' ? DEX_ROUTERS[network]?.uniswap : DEX_ROUTERS[network]?.katana);

    if (!routerAddress) {
      throw new Error(`No default router address for ${network}`);
    }

    contractName = 'UniversalDexDepositor';
    contractPath = `${contractName}.sol`;
    constructorArgs = [routerAddress, options.diamond, usdcAddress, ownerAddress];
    constructorTypes = ['address', 'address', 'address', 'address'];
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
    .name('deploy-depositor')
    .description('Deploy a DEX depositor contract using CREATE3')
    .argument('<network>', 'Network to deploy to (ronin|base|devnet1|devnet2)')
    .requiredOption('--diamond <address>', 'Diamond proxy address')
    .option('--router <address>', 'DEX router address (optional, uses defaults)')
    .option('--usdc <address>', 'USDC token address (optional, uses defaults)')
    .option('--weth <address>', 'WETH token address (optional, uses defaults, for dummy depositor only)')
    .option('--owner <address>', 'Owner address (optional, defaults to deployer)')
    .option('--skip-verification', 'Skip contract verification on block explorer')
    .parse();

  const [network] = program.args;
  const options = program.opts();

  const depositorType =
    (network === 'devnet1' || network === 'devnet2') ? 'dummy'
    : 'universal';
  const routerType = network === 'base' ? 'Uniswap' : 'Katana';
  const clients = createClients(network);

  console.log('╔════════════════════════════════════════╗');
  console.log('║       Deploy DEX Depositor             ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Network:     ${network.toUpperCase()}`);
  console.log(`Depositor:   ${depositorType.toUpperCase()}`);
  console.log(`Diamond:     ${options.diamond}`);

  const ownerAddress = options.owner || clients.account.address;
  const usdcAddress = options.usdc || TOKEN_CONFIGS[network]?.usdc?.address;

  if (depositorType === 'dummy') {
    const wethAddress = options.weth || TOKEN_CONFIGS[network]?.weth?.address;
    console.log(`WETH:        ${wethAddress}`);
    console.log(`USDC:        ${usdcAddress}`);
  } else {
    const routerAddress = options.router ||
      (network === 'base' ? DEX_ROUTERS[network]?.uniswap : DEX_ROUTERS[network]?.katana);
    console.log(`Router Type: ${routerType}`);
    console.log(`Router:      ${routerAddress}`);
    console.log(`USDC:        ${usdcAddress}`);
  }

  console.log(`Deployer:    ${clients.account.address}`);
  console.log(`Owner:       ${ownerAddress}`);
  console.log(`Salt:        ${CREATE3_SALT}`);
  console.log('─────────────────────────────────────────\n');

  console.log('🚀 Deploying depositor with CREATE3...\n');

  let contractName: string;
  let contractPath: string;
  let constructorArgs: any[];
  let constructorTypes: string[];

  if (depositorType === 'dummy') {
    const wethAddress = options.weth || TOKEN_CONFIGS[network]?.weth?.address;
    contractName = 'DummyDexDepositor';
    contractPath = 'DummyDexDepositor.sol';
    constructorArgs = [wethAddress, options.diamond, usdcAddress, ownerAddress];
    constructorTypes = ['address', 'address', 'address', 'address'];
  } else {
    const routerAddress = options.router ||
      (network === 'base' ? DEX_ROUTERS[network]?.uniswap : DEX_ROUTERS[network]?.katana);
    contractName = 'UniversalDexDepositor';
    contractPath = `${contractName}.sol`;
    constructorArgs = [routerAddress, options.diamond, usdcAddress, ownerAddress];
    constructorTypes = ['address', 'address', 'address', 'address'];
  }

  const result = await deployDepositor(network, { ...options, skipVerification: true });

  if (result.alreadyDeployed) {
    console.log('╔════════════════════════════════════════╗');
    console.log('║      Already Deployed                  ║');
    console.log('╚════════════════════════════════════════╝');
    console.log(`Depositor Address: ${result.address}`);
    console.log(`Owner Address:     ${ownerAddress}`);
    console.log('\n✅ Depositor already deployed at this address!');
  } else {
    console.log('╔════════════════════════════════════════╗');
    console.log('║         Deployment Success             ║');
    console.log('╚════════════════════════════════════════╝');
    console.log(`Depositor Address: ${result.address}`);
    console.log(`Owner Address:     ${ownerAddress}`);
    console.log(`Transaction:       ${result.txHash}`);
    console.log(`Gas Used:          ${result.gasUsed}`);
    console.log('\n✅ Depositor deployed successfully!');
  }

  if (!options.skipVerification) {
    const verificationConfig = getVerificationConfig(network);
    if (verificationConfig) {
      const verifyResult = await verifyContract(
        result.address,
        contractName,
        contractPath,
        'src/depositors',
        constructorArgs,
        constructorTypes,
        verificationConfig
      );

      if (verifyResult.success) {
        console.log('✅ Contract verified on block explorer!');
      } else if (verifyResult.error) {
        console.log(`⚠️  Verification failed: ${verifyResult.error}`);
      }
    }
  }
}

main().catch((error) => {
  console.error('\n❌ Deployment failed:', error.message);
  process.exit(1);
});

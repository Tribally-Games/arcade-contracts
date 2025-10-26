#!/usr/bin/env bun

import { type Hex } from 'viem';
import { readFileSync } from 'fs';
import { join } from 'path';
import { createClients } from './utils';
import { deployWithCreate3AndLog } from './create3-deploy';

const TARGET = process.env.GEMFORGE_DEPLOY_TARGET;

const ADAPTER_CONFIGS = {
  ronin: {
    name: 'Ronin',
    adapterName: 'KatanaSwapAdapter',
    adapterPath: 'KatanaSwapAdapter.sol',
    routerAddress: '0x5f0acdd3ec767514ff1bf7e79949640bf94576bd' as Hex,
    usdcAddress: '0x0b7007c13325c48911f73a2dad5fa5dcbf808adc' as Hex,
    salt: '0x4b4154414e415f4144415054455200000000000000000000000000000000beee' as Hex,
  },
  base: {
    name: 'Base',
    adapterName: 'UniswapV3SwapAdapter',
    adapterPath: 'UniswapV3SwapAdapter.sol',
    routerAddress: '0x2626664c2603336E57B271c5C0b26F421741e481' as Hex,
    usdcAddress: '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913' as Hex,
    salt: '0x554e49535741505f4144415054455200000000000000000000000000000000ef' as Hex,
  },
} as const;

const KNOWN_USDC_ADDRESS = '0x5FbDB2315678afecb367f032d93F642f64180aa3' as Hex;
const KNOWN_TRIBAL_ADDRESS = '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512' as Hex;

async function deployDexAdapter(target: string) {
  const config = ADAPTER_CONFIGS[target as keyof typeof ADAPTER_CONFIGS];

  if (!config) {
    console.log(`No DEX adapter configured for target: ${target}`);
    return;
  }

  console.log('\n╔════════════════════════════════════════╗');
  console.log('║     DEX Adapter Deployment             ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Network:        ${config.name}`);
  console.log(`Adapter:        ${config.adapterName}`);

  const clients = createClients(target);

  const result = await deployWithCreate3AndLog(
    clients,
    {
      contractName: config.adapterName,
      contractPath: config.adapterPath,
      constructorArgs: [config.routerAddress, config.usdcAddress, clients.account.address],
      constructorTypes: ['address', 'address', 'address'],
      salt: config.salt,
    },
    `${config.name} DEX Adapter`
  );

  console.log('\n📋 Deployment Summary:');
  console.log(`  Address:        ${result.address}`);
  console.log(`  Router:         ${config.routerAddress}`);
  console.log(`  USDC:           ${config.usdcAddress}`);
  console.log(`  Owner:          ${clients.account.address}`);
  console.log('─────────────────────────────────────────\n');

  return result.address;
}

async function deployTestTokens() {
  console.log('Running predeploy script for local target...');

  const clients = createClients('local');

  console.log(`Using deployer address: ${clients.account.address}`);

  const artifactPath = join(process.cwd(), 'out/TestERC20.sol/TestERC20.json');
  const artifact = JSON.parse(readFileSync(artifactPath, 'utf-8'));

  async function deployToken(
    name: string,
    symbol: string,
    decimals: number,
    knownAddress: Hex,
    mintAmount: bigint
  ) {
    const bytecode = artifact.bytecode.object as Hex;

    const code = await clients.publicClient.getCode({ address: knownAddress });

    if (code && code !== '0x') {
      console.log(`✓ ${name} already deployed at ${knownAddress}`);
      return knownAddress;
    }

    console.log(`Deploying ${name} (${symbol}) with ${decimals} decimals...`);

    const hash = await clients.walletClient.deployContract({
      abi: artifact.abi,
      bytecode: bytecode,
      args: [name, symbol, decimals],
      account: clients.account,
    });

    console.log(`Deploy transaction: ${hash}`);

    const receipt = await clients.publicClient.waitForTransactionReceipt({ hash });

    if (!receipt.contractAddress) {
      throw new Error('Failed to deploy contract - no address in receipt');
    }

    console.log(`Minting initial balance to deployer...`);

    const mintHash = await clients.walletClient.writeContract({
      address: receipt.contractAddress,
      abi: artifact.abi,
      functionName: 'mint',
      args: [clients.account.address, mintAmount],
      account: clients.account,
    });

    await clients.publicClient.waitForTransactionReceipt({ hash: mintHash });

    console.log(`✓ ${name} deployed successfully`);
    console.log(`Token address: ${receipt.contractAddress}`);

    return receipt.contractAddress;
  }

  await deployToken('TestUSDC', 'tUSDC', 6, KNOWN_USDC_ADDRESS, 1000000000n);
  await deployToken('TestTRIBAL', 'tTRIBAL', 18, KNOWN_TRIBAL_ADDRESS, 1000000000000000000000n);
}

async function main() {
  if (!TARGET) {
    throw new Error('GEMFORGE_DEPLOY_TARGET not set');
  }

  if (TARGET === 'local') {
    await deployTestTokens();
  } else if (TARGET === 'ronin' || TARGET === 'base') {
    console.log(`Running predeploy script for ${TARGET} target...`);
    await deployDexAdapter(TARGET);
  } else {
    console.log(`Skipping predeploy - target is ${TARGET}`);
  }
}

main().catch((error) => {
  console.error('Predeploy script failed:', error);
  process.exit(1);
});

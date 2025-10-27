#!/usr/bin/env bun

import { type Hex } from 'viem';
import { readFileSync } from 'fs';
import { join } from 'path';
import { createClients } from './utils';

const TARGET = process.env.GEMFORGE_DEPLOY_TARGET;

const KNOWN_WETH_ADDRESS = '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9' as Hex;
const KNOWN_USDC_ADDRESS = '0x5FbDB2315678afecb367f032d93F642f64180aa3' as Hex;
const KNOWN_TRIBAL_ADDRESS = '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512' as Hex;
const KNOWN_ADAPTER_ADDRESS = '0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9' as Hex;

async function deployLocalDevnetContracts() {
  console.log('Running predeploy script for local devnet target...');

  const clients = createClients(TARGET!);

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

  const wethArtifactPath = join(process.cwd(), 'out/MockWETH.sol/MockWETH.json');
  const wethArtifact = JSON.parse(readFileSync(wethArtifactPath, 'utf-8'));

  const wethCode = await clients.publicClient.getCode({ address: KNOWN_WETH_ADDRESS });
  let wethAddress: Hex;

  if (wethCode && wethCode !== '0x') {
    console.log(`✓ MockWETH already deployed at ${KNOWN_WETH_ADDRESS}`);
    wethAddress = KNOWN_WETH_ADDRESS;
  } else {
    console.log('Deploying MockWETH...');
    const wethHash = await clients.walletClient.deployContract({
      abi: wethArtifact.abi,
      bytecode: wethArtifact.bytecode.object as Hex,
      args: [],
      account: clients.account,
    });

    console.log(`Deploy transaction: ${wethHash}`);
    const wethReceipt = await clients.publicClient.waitForTransactionReceipt({ hash: wethHash });

    if (!wethReceipt.contractAddress) {
      throw new Error('Failed to deploy MockWETH - no address in receipt');
    }

    wethAddress = wethReceipt.contractAddress;
    console.log(`✓ MockWETH deployed successfully at ${wethAddress}`);

    console.log('Wrapping 1000 ETH to WETH...');
    const depositHash = await clients.walletClient.sendTransaction({
      to: wethAddress,
      value: 1000n * 10n ** 18n,
      account: clients.account,
    });
    await clients.publicClient.waitForTransactionReceipt({ hash: depositHash });
    console.log('✓ Wrapped 1000 ETH to WETH');
  }

  const adapterArtifactPath = join(process.cwd(), 'out/DummyDexAdapter.sol/DummyDexAdapter.json');
  const adapterArtifact = JSON.parse(readFileSync(adapterArtifactPath, 'utf-8'));

  const adapterCode = await clients.publicClient.getCode({ address: KNOWN_ADAPTER_ADDRESS });

  if (adapterCode && adapterCode !== '0x') {
    console.log(`✓ DummyDexAdapter already deployed at ${KNOWN_ADAPTER_ADDRESS}`);
  } else {
    console.log('Deploying DummyDexAdapter...');
    const adapterHash = await clients.walletClient.deployContract({
      abi: adapterArtifact.abi,
      bytecode: adapterArtifact.bytecode.object as Hex,
      args: [wethAddress, KNOWN_USDC_ADDRESS],
      account: clients.account,
    });

    console.log(`Deploy transaction: ${adapterHash}`);
    const adapterReceipt = await clients.publicClient.waitForTransactionReceipt({ hash: adapterHash });

    if (!adapterReceipt.contractAddress) {
      throw new Error('Failed to deploy DummyDexAdapter - no address in receipt');
    }

    console.log(`✓ DummyDexAdapter deployed successfully at ${adapterReceipt.contractAddress}`);

    console.log('Adding initial liquidity (100 WETH + 200,000 USDC)...');

    const wethAmount = 100n * 10n ** 18n;
    const usdcAmount = 200000n * 10n ** 6n;

    const approveWethHash = await clients.walletClient.writeContract({
      address: wethAddress,
      abi: wethArtifact.abi,
      functionName: 'approve',
      args: [adapterReceipt.contractAddress, wethAmount],
      account: clients.account,
    });
    await clients.publicClient.waitForTransactionReceipt({ hash: approveWethHash });

    const approveUsdcHash = await clients.walletClient.writeContract({
      address: KNOWN_USDC_ADDRESS,
      abi: artifact.abi,
      functionName: 'approve',
      args: [adapterReceipt.contractAddress, usdcAmount],
      account: clients.account,
    });
    await clients.publicClient.waitForTransactionReceipt({ hash: approveUsdcHash });

    const addLiquidityHash = await clients.walletClient.writeContract({
      address: adapterReceipt.contractAddress,
      abi: adapterArtifact.abi,
      functionName: 'addLiquidity',
      args: [wethAmount, usdcAmount],
      account: clients.account,
    });
    await clients.publicClient.waitForTransactionReceipt({ hash: addLiquidityHash });

    console.log('✓ Initial liquidity added (100 WETH + 200,000 USDC)');
    console.log(`  Initial price: 1 WETH = 2,000 USDC`);
  }
}

async function main() {
  if (!TARGET) {
    throw new Error('GEMFORGE_DEPLOY_TARGET not set');
  }

  if (TARGET === 'devnet1' || TARGET === 'devnet2') {
    await deployLocalDevnetContracts();
  } else if (TARGET === 'ronin' || TARGET === 'base') {
    console.log(`Running predeploy script for ${TARGET} target...`);
    console.log('\n╔════════════════════════════════════════╗');
    console.log('║     DEX Adapter Verification           ║');
    console.log('╚════════════════════════════════════════╝\n');

    const configPath = join(process.cwd(), 'gemforge.config.cjs');
    const config = require(configPath);

    const targetConfig = config.targets[TARGET];
    if (!targetConfig || !targetConfig.initArgs || targetConfig.initArgs.length < 4) {
      throw new Error(`Invalid target configuration for ${TARGET} in gemforge.config.cjs`);
    }

    const adapterAddress = targetConfig.initArgs[3] as Hex;
    console.log(`Checking adapter deployment at: ${adapterAddress}`);

    const clients = createClients(TARGET);
    const code = await clients.publicClient.getCode({ address: adapterAddress });

    if (!code || code === '0x') {
      console.error('\n❌ DEX Adapter not deployed!');
      console.error('\nTo deploy the adapter:');
      console.error(`  1. Run: bun run scripts/deploy-adapter.ts ${TARGET}`);
      console.error(`  2. Update gemforge.config.cjs targets.${TARGET}.initArgs[3] with the deployed adapter address`);
      console.error(`  3. Retry deployment\n`);
      throw new Error('DEX Adapter must be deployed before deploying the Arcade contract');
    }

    console.log('✅ DEX Adapter verified at address\n');
  } else {
    console.log(`Skipping predeploy - target is ${TARGET}`);
  }
}

main().catch((error) => {
  console.error('Predeploy script failed:', error);
  process.exit(1);
});

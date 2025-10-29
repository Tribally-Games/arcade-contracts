#!/usr/bin/env bun

import { type Hex } from 'viem';
import { readFileSync } from 'fs';
import { join } from 'path';
import { createClients } from './utils';
import { deployWithCreate3, getPredictedAddress } from './create3-deploy';

const TARGET = process.env.GEMFORGE_DEPLOY_TARGET;

const USDC_SALT = '0x555344435f544553545f544f4b454e0000000000000000000000000000000001' as Hex;
const TRIBAL_SALT = '0x545249424144414c5f544553545f544f4b454e00000000000000000000000001' as Hex;
const WETH_SALT = '0x574554485f4d4f434b5f544f4b454e0000000000000000000000000000000001' as Hex;
const ADAPTER_SALT = '0x4445585f41444150544552000000000000000000000000000000000000013aff' as Hex;

async function deployLocalDevnetContracts() {
  console.log('Running predeploy script for local devnet target...');

  const clients = createClients(TARGET!);

  console.log(`Using deployer address: ${clients.account.address}`);

  const erc20Artifact = JSON.parse(
    readFileSync(join(process.cwd(), 'out/TestERC20.sol/TestERC20.json'), 'utf-8')
  );
  const wethArtifact = JSON.parse(
    readFileSync(join(process.cwd(), 'out/MockWETH.sol/MockWETH.json'), 'utf-8')
  );

  console.log('\n📦 Deploying USDC with CREATE3...');
  const usdcResult = await deployWithCreate3(clients, {
    contractName: 'TestERC20',
    contractPath: 'TestERC20.sol',
    constructorArgs: ['TestUSDC', 'tUSDC', 6],
    constructorTypes: ['string', 'string', 'uint8'],
    salt: USDC_SALT,
  });
  const usdcAddress = usdcResult.address;
  console.log(`✓ USDC deployed at ${usdcAddress}`);

  if (!usdcResult.alreadyDeployed) {
    console.log('Minting USDC to deployer...');
    const mintHash = await clients.walletClient.writeContract({
      address: usdcAddress,
      abi: erc20Artifact.abi,
      functionName: 'mint',
      args: [clients.account.address, 10000000000n],
      account: clients.account,
    });
    await clients.publicClient.waitForTransactionReceipt({ hash: mintHash });
    console.log('✓ Minted 10,000 USDC to deployer');
  }

  console.log('\n📦 Deploying TRIBAL with CREATE3...');
  const tribalResult = await deployWithCreate3(clients, {
    contractName: 'TestERC20',
    contractPath: 'TestERC20.sol',
    constructorArgs: ['TestTRIBAL', 'tTRIBAL', 18],
    constructorTypes: ['string', 'string', 'uint8'],
    salt: TRIBAL_SALT,
  });
  const tribalAddress = tribalResult.address;
  console.log(`✓ TRIBAL deployed at ${tribalAddress}`);

  if (!tribalResult.alreadyDeployed) {
    console.log('Minting TRIBAL to deployer...');
    const mintHash = await clients.walletClient.writeContract({
      address: tribalAddress,
      abi: erc20Artifact.abi,
      functionName: 'mint',
      args: [clients.account.address, 1000000000000000000000n],
      account: clients.account,
    });
    await clients.publicClient.waitForTransactionReceipt({ hash: mintHash });
    console.log('✓ Minted 1,000 TRIBAL to deployer');
  }

  console.log('\n📦 Deploying MockWETH with CREATE3...');
  const wethResult = await deployWithCreate3(clients, {
    contractName: 'MockWETH',
    contractPath: 'MockWETH.sol',
    constructorArgs: [],
    constructorTypes: [],
    salt: WETH_SALT,
  });
  const wethAddress = wethResult.address;
  console.log(`✓ MockWETH deployed at ${wethAddress}`);

  if (!wethResult.alreadyDeployed) {
    console.log('Wrapping 1000 ETH to WETH...');
    const depositHash = await clients.walletClient.sendTransaction({
      to: wethAddress,
      value: 1000n * 10n ** 18n,
      account: clients.account,
    });
    await clients.publicClient.waitForTransactionReceipt({ hash: depositHash });
    console.log('✓ Wrapped 1000 ETH to WETH');
  }

  console.log('\n📦 Deploying DummyDexAdapter with CREATE3...');
  const adapterResult = await deployWithCreate3(clients, {
    contractName: 'DummyDexAdapter',
    contractPath: 'DummyDexAdapter.sol',
    constructorArgs: [wethAddress, usdcAddress, clients.account.address],
    constructorTypes: ['address', 'address', 'address'],
    salt: ADAPTER_SALT,
  });
  const adapterAddress = adapterResult.address;
  console.log(`✓ DummyDexAdapter deployed at ${adapterAddress}`);

  if (!adapterResult.alreadyDeployed) {
    console.log('\n💧 Adding initial liquidity (100 WETH + 100 USDC)...');

    const wethAmount = 100n * 10n ** 18n;
    const usdcAmount = 100n * 10n ** 6n;

    const approveWethHash = await clients.walletClient.writeContract({
      address: wethAddress,
      abi: wethArtifact.abi,
      functionName: 'approve',
      args: [adapterAddress, wethAmount],
      account: clients.account,
    });
    await clients.publicClient.waitForTransactionReceipt({ hash: approveWethHash });

    const approveUsdcHash = await clients.walletClient.writeContract({
      address: usdcAddress,
      abi: erc20Artifact.abi,
      functionName: 'approve',
      args: [adapterAddress, usdcAmount],
      account: clients.account,
    });
    await clients.publicClient.waitForTransactionReceipt({ hash: approveUsdcHash });

    const adapterArtifact = JSON.parse(
      readFileSync(join(process.cwd(), 'out/DummyDexAdapter.sol/DummyDexAdapter.json'), 'utf-8')
    );

    const addLiquidityHash = await clients.walletClient.writeContract({
      address: adapterAddress,
      abi: adapterArtifact.abi,
      functionName: 'addLiquidity',
      args: [wethAmount, usdcAmount],
      account: clients.account,
    });
    await clients.publicClient.waitForTransactionReceipt({ hash: addLiquidityHash });

    console.log('✓ Initial liquidity added (100 WETH + 100 USDC)');
    console.log('  Initial price: 1 WETH = 1 USDC');
  }

  console.log('\n✅ All contracts deployed successfully!\n');
  console.log('Contract Addresses:');
  console.log(`  USDC:    ${usdcAddress}`);
  console.log(`  TRIBAL:  ${tribalAddress}`);
  console.log(`  WETH:    ${wethAddress}`);
  console.log(`  Adapter: ${adapterAddress}`);
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

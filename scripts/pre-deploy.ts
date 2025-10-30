#!/usr/bin/env bun

import { type Hex } from 'viem';
import { readFileSync } from 'fs';
import { join } from 'path';
import { createClients } from './utils';
import { deployWithCreate3 } from './create3-deploy';

const TARGET = process.env.GEMFORGE_DEPLOY_TARGET;

const USDC_SALT = '0x555344435f544553545f544f4b454e0000000000000000000000000000000001' as Hex;
const TRIBAL_SALT = '0x545249424144414c5f544553545f544f4b454e00000000000000000000000001' as Hex;
const WETH_SALT = '0x574554485f4d4f434b5f544f4b454e0000000000000000000000000000000001' as Hex;

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

  console.log('\n✅ All test tokens deployed successfully!\n');
  console.log('Contract Addresses:');
  console.log(`  USDC:    ${usdcAddress}`);
  console.log(`  TRIBAL:  ${tribalAddress}`);
  console.log(`  WETH:    ${wethAddress}`);
}

async function main() {
  if (!TARGET) {
    throw new Error('GEMFORGE_DEPLOY_TARGET not set');
  }

  if (TARGET === 'devnet1' || TARGET === 'devnet2') {
    await deployLocalDevnetContracts();
  } else {
    console.log(`Skipping predeploy - target is ${TARGET}`);
  }
}

main().catch((error) => {
  console.error('Predeploy script failed:', error);
  process.exit(1);
});

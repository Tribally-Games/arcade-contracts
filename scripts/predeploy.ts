#!/usr/bin/env bun

import { createPublicClient, createWalletClient, http, getContract, parseAbi } from 'viem';
import { mnemonicToAccount } from 'viem/accounts';
import { foundry } from 'viem/chains';
import { readFileSync } from 'fs';
import { join } from 'path';

const TARGET = process.env.GEMFORGE_DEPLOY_TARGET;

if (TARGET !== 'local') {
  console.log(`Skipping predeploy - target is ${TARGET}, not local`);
  process.exit(0);
}

console.log('Running predeploy script for local target...');

const configPath = join(process.cwd(), 'gemforge.config.cjs');
const config = require(configPath);

const walletConfig = config.wallets.local_wallet;

if (walletConfig.type !== 'mnemonic') {
  throw new Error('Expected mnemonic wallet type for local_wallet');
}

const account = mnemonicToAccount(walletConfig.config.words, {
  addressIndex: walletConfig.config.index,
});

console.log(`Using deployer address: ${account.address}`);

const publicClient = createPublicClient({
  chain: foundry,
  transport: http('http://localhost:8545'),
});

const walletClient = createWalletClient({
  account,
  chain: foundry,
  transport: http('http://localhost:8545'),
});

const artifactPath = join(process.cwd(), 'out/TestERC20.sol/TestERC20.json');
const artifact = JSON.parse(readFileSync(artifactPath, 'utf-8'));

const KNOWN_TOKEN_ADDRESS = '0x5FbDB2315678afecb367f032d93F642f64180aa3';

async function main() {
  const bytecode = artifact.bytecode.object as `0x${string}`;

  const code = await publicClient.getCode({ address: KNOWN_TOKEN_ADDRESS });

  if (code && code !== '0x') {
    console.log(`✓ Token already deployed at ${KNOWN_TOKEN_ADDRESS}`);
    console.log(`Token address: ${KNOWN_TOKEN_ADDRESS}`);
    return;
  }

  console.log('Deploying TestERC20 token with 6 decimals...');

  const hash = await walletClient.deployContract({
    abi: artifact.abi,
    bytecode: bytecode,
    args: [],
  });

  console.log(`Deploy transaction: ${hash}`);

  const receipt = await publicClient.waitForTransactionReceipt({ hash });

  if (!receipt.contractAddress) {
    throw new Error('Failed to deploy contract - no address in receipt');
  }

  console.log(`Minting initial balance to deployer...`);

  const mintHash = await walletClient.writeContract({
    address: receipt.contractAddress,
    abi: artifact.abi,
    functionName: 'mint',
    args: [account.address, 1000000000n],
  });

  await publicClient.waitForTransactionReceipt({ hash: mintHash });

  console.log(`✓ Token deployed successfully`);
  console.log(`Token address: ${receipt.contractAddress}`);
  console.log(`Deployer balance: 1,000,000,000 (1000 with 6 decimals)`);
}

main().catch((error) => {
  console.error('Predeploy script failed:', error);
  process.exit(1);
});

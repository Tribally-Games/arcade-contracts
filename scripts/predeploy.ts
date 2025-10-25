#!/usr/bin/env bun

import { parseAbi } from 'viem';
import { readFileSync } from 'fs';
import { join } from 'path';
import { createClients } from './utils';

const TARGET = process.env.GEMFORGE_DEPLOY_TARGET;

if (TARGET !== 'local') {
  console.log(`Skipping predeploy - target is ${TARGET}, not local`);
  process.exit(0);
}

console.log('Running predeploy script for local target...');

const { publicClient, walletClient, account } = createClients('local');

console.log(`Using deployer address: ${account.address}`);

const artifactPath = join(process.cwd(), 'out/TestERC20.sol/TestERC20.json');
const artifact = JSON.parse(readFileSync(artifactPath, 'utf-8'));

const KNOWN_USDC_ADDRESS = '0x5FbDB2315678afecb367f032d93F642f64180aa3';
const KNOWN_TRIBAL_ADDRESS = '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512';

async function deployToken(
  name: string,
  symbol: string,
  decimals: number,
  knownAddress: `0x${string}`,
  mintAmount: bigint
) {
  const bytecode = artifact.bytecode.object as `0x${string}`;

  const code = await publicClient.getCode({ address: knownAddress });

  if (code && code !== '0x') {
    console.log(`✓ ${name} already deployed at ${knownAddress}`);
    return knownAddress;
  }

  console.log(`Deploying ${name} (${symbol}) with ${decimals} decimals...`);

  const hash = await walletClient.deployContract({
    abi: artifact.abi,
    bytecode: bytecode,
    args: [name, symbol, decimals],
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
    args: [account.address, mintAmount],
  });

  await publicClient.waitForTransactionReceipt({ hash: mintHash });

  console.log(`✓ ${name} deployed successfully`);
  console.log(`Token address: ${receipt.contractAddress}`);

  return receipt.contractAddress;
}

async function main() {
  await deployToken('TestUSDC', 'tUSDC', 6, KNOWN_USDC_ADDRESS, 1000000000n);
  await deployToken('TestTRIBAL', 'tTRIBAL', 18, KNOWN_TRIBAL_ADDRESS, 1000000000000000000000n);
}

main().catch((error) => {
  console.error('Predeploy script failed:', error);
  process.exit(1);
});

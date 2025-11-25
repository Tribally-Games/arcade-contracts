#!/usr/bin/env bun

import { Command } from 'commander';
import { type Hex, isAddress } from 'viem';
import { createClients } from './utils';
import { DIAMOND_ABI } from './gateway-utils';
import { readFileSync } from 'fs';
import { join } from 'path';

const DEPLOYMENTS_FILE = join(process.cwd(), 'gemforge.deployments.json');

interface DeploymentContract {
  name: string;
  onChain: {
    address: string;
  };
}

interface NetworkDeployments {
  chainId: number;
  contracts: DeploymentContract[];
}

interface Deployments {
  [network: string]: NetworkDeployments;
}

function loadDiamondAddress(target: string): Hex {
  const deployments: Deployments = JSON.parse(readFileSync(DEPLOYMENTS_FILE, 'utf-8'));

  const networkDeployments = deployments[target];
  if (!networkDeployments) {
    throw new Error(`No deployments found for target: ${target}`);
  }

  const diamondContract = networkDeployments.contracts.find(c => c.name === 'DiamondProxy');
  if (!diamondContract) {
    throw new Error(`DiamondProxy not found in deployments for target: ${target}`);
  }

  return diamondContract.onChain.address as Hex;
}

async function main() {
  const program = new Command();

  program
    .name('transfer-ownership')
    .description('Transfer diamond ownership to a new address')
    .argument('<target>', 'Gemforge target (ronin|base|devnet1|devnet2)')
    .argument('<new-owner>', 'New owner address')
    .parse();

  const [target, newOwner] = program.args;

  if (!['ronin', 'base', 'devnet1', 'devnet2'].includes(target)) {
    throw new Error(`Invalid target: ${target}. Valid targets: ronin, base, devnet1, devnet2`);
  }

  if (!isAddress(newOwner)) {
    throw new Error(`Invalid new owner address: ${newOwner}`);
  }

  const { publicClient, walletClient, account } = createClients(target);
  const diamondAddress = loadDiamondAddress(target);

  const currentOwner = await publicClient.readContract({
    address: diamondAddress,
    abi: DIAMOND_ABI,
    functionName: 'owner',
  }) as Hex;

  console.log('╔════════════════════════════════════════╗');
  console.log('║       Transfer Diamond Ownership       ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Target:        ${target.toUpperCase()}`);
  console.log(`Diamond:       ${diamondAddress}`);
  console.log(`Current Owner: ${currentOwner}`);
  console.log(`New Owner:     ${newOwner}`);
  console.log(`Caller:        ${account.address}`);
  console.log('─────────────────────────────────────────\n');

  if (currentOwner.toLowerCase() !== account.address.toLowerCase()) {
    throw new Error(`Caller ${account.address} is not the current owner ${currentOwner}`);
  }

  if (currentOwner.toLowerCase() === newOwner.toLowerCase()) {
    console.log('⚠️  New owner is already the current owner. No transfer needed.');
    return;
  }

  console.log('🔄 Transferring ownership...\n');

  const txHash = await walletClient.writeContract({
    address: diamondAddress,
    abi: DIAMOND_ABI,
    functionName: 'transferOwnership',
    args: [newOwner as Hex],
    account,
    chain: null,
  });

  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });

  const verifiedOwner = await publicClient.readContract({
    address: diamondAddress,
    abi: DIAMOND_ABI,
    functionName: 'owner',
  }) as Hex;

  if (verifiedOwner.toLowerCase() !== newOwner.toLowerCase()) {
    throw new Error(`Ownership transfer verification failed. Expected ${newOwner}, got ${verifiedOwner}`);
  }

  console.log('╔════════════════════════════════════════╗');
  console.log('║         Transfer Complete              ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Transaction:   ${txHash}`);
  console.log(`Gas Used:      ${receipt.gasUsed}`);
  console.log(`New Owner:     ${verifiedOwner}`);
  console.log('\n✅ Ownership transferred successfully!');
}

main().catch((error) => {
  console.error('\n❌ Transfer failed:', error.message);
  process.exit(1);
});

#!/usr/bin/env bun

import { Command } from 'commander';
import { type Hex, isAddress, encodeFunctionData } from 'viem';
import { createClients, getDeployedAddress, loadGemforgeConfig } from './utils';
import { DIAMOND_ABI } from './gateway-utils';

interface TargetConfig {
  network: string;
  wallet: string;
  upgrades?: {
    manualCut?: boolean;
  };
}

function isManualCut(target: string): boolean {
  const config = loadGemforgeConfig();
  const targetConfig = (config.targets as Record<string, TargetConfig>)[target];
  return targetConfig?.upgrades?.manualCut === true;
}

async function main() {
  const program = new Command();

  program
    .name('set-signer')
    .description('Set the signer on the diamond proxy')
    .argument('<target>', 'Gemforge target (ronin|base|devnet1|devnet2|baseFork)')
    .argument('<new-signer>', 'New signer address')
    .parse();

  const [target, newSigner] = program.args;

  const validTargets = ['ronin', 'base', 'devnet1', 'devnet2', 'baseFork'];
  if (!validTargets.includes(target)) {
    throw new Error(`Invalid target: ${target}. Valid targets: ${validTargets.join(', ')}`);
  }

  if (!isAddress(newSigner)) {
    throw new Error(`Invalid new signer address: ${newSigner}`);
  }

  const { publicClient, walletClient, account } = createClients(target);
  const diamondAddress = getDeployedAddress(target, 'DiamondProxy');
  const manualCut = isManualCut(target);

  const currentSigner = await publicClient.readContract({
    address: diamondAddress,
    abi: DIAMOND_ABI,
    functionName: 'signer',
  }) as Hex;

  console.log('╔════════════════════════════════════════╗');
  console.log('║           Set Diamond Signer           ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Target:         ${target.toUpperCase()}`);
  console.log(`Diamond:        ${diamondAddress}`);
  console.log(`Current Signer: ${currentSigner}`);
  console.log(`New Signer:     ${newSigner}`);
  console.log(`Manual Cut:     ${manualCut}`);
  console.log('─────────────────────────────────────────\n');

  if (currentSigner.toLowerCase() === newSigner.toLowerCase()) {
    console.log('⚠️  New signer is already the current signer. No change needed.');
    return;
  }

  if (manualCut) {
    const calldata = encodeFunctionData({
      abi: DIAMOND_ABI,
      functionName: 'setSigner',
      args: [newSigner as Hex],
    });

    const setSignerAbi = [{
      type: 'function',
      name: 'setSigner',
      inputs: [{ name: '_signer', type: 'address' }],
      outputs: [],
      stateMutability: 'nonpayable',
    }];

    console.log('╔════════════════════════════════════════╗');
    console.log('║     Gnosis SAFE Transaction Data       ║');
    console.log('╚════════════════════════════════════════╝');
    console.log(`To:       ${diamondAddress}`);
    console.log(`Value:    0`);
    console.log(`Data:     ${calldata}`);
    console.log(`\nABI (paste into SAFE UI):\n${JSON.stringify(setSignerAbi)}`);
    return;
  }

  console.log(`Caller: ${account.address}`);
  console.log('🔄 Setting signer...\n');

  const txHash = await walletClient.writeContract({
    address: diamondAddress,
    abi: DIAMOND_ABI,
    functionName: 'setSigner',
    args: [newSigner as Hex],
    account,
    chain: null,
  });

  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });

  const verifiedSigner = await publicClient.readContract({
    address: diamondAddress,
    abi: DIAMOND_ABI,
    functionName: 'signer',
  }) as Hex;

  if (verifiedSigner.toLowerCase() !== newSigner.toLowerCase()) {
    throw new Error(`Signer update verification failed. Expected ${newSigner}, got ${verifiedSigner}`);
  }

  console.log('╔════════════════════════════════════════╗');
  console.log('║           Update Complete              ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Transaction: ${txHash}`);
  console.log(`Gas Used:    ${receipt.gasUsed}`);
  console.log(`New Signer:  ${verifiedSigner}`);
  console.log('\n✅ Signer updated successfully!');
}

main().catch((error) => {
  console.error('\n❌ Set signer failed:', error.message);
  process.exit(1);
});

#!/usr/bin/env bun

import { Command } from 'commander';
import { createClients } from './utils';
import { DIAMOND_ABI } from './gateway-utils';
import { getContract } from 'viem';

async function main() {
  const program = new Command();

  program
    .name('update-gateway-adapter')
    .description('Update the swap adapter in the Gateway')
    .argument('<network>', 'Network (ronin|base|local1|local2)')
    .argument('<diamond-address>', 'Diamond contract address')
    .argument('<new-adapter-address>', 'New swap adapter address')
    .option('-y, --yes', 'Skip confirmation prompt')
    .parse();

  const [network, diamondAddressRaw, newAdapterAddressRaw] = program.args;
  const options = program.opts();

  if (!['ronin', 'base', 'local1', 'local2'].includes(network)) {
    console.error(`Invalid network: ${network}`);
    console.error('Valid networks: ronin, base, local1, local2');
    process.exit(1);
  }

  const diamondAddress = diamondAddressRaw as `0x${string}`;
  const newAdapterAddress = newAdapterAddressRaw as `0x${string}`;

  const { publicClient, walletClient, account } = createClients(network);

  const configFacet = getContract({
    address: diamondAddress,
    abi: DIAMOND_ABI,
    client: { public: publicClient, wallet: walletClient },
  });

  console.log('╔════════════════════════════════════════╗');
  console.log('║      Update Gateway Swap Adapter       ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Network:        ${network.toUpperCase()}`);
  console.log(`Diamond:        ${diamondAddress}`);
  console.log(`Caller:         ${account.address}`);
  console.log('─────────────────────────────────────────\n');

  console.log('🔍 Fetching current adapter...\n');

  const currentAdapter = await configFacet.read.swapAdapter();
  console.log(`Current Adapter: ${currentAdapter}`);
  console.log(`New Adapter:     ${newAdapterAddress}\n`);

  if (currentAdapter === newAdapterAddress) {
    console.log('⚠️  Warning: New adapter is the same as current adapter');
  }

  if (!options.yes) {
    const readline = await import('readline');
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });

    const answer = await new Promise<string>((resolve) => {
      rl.question('Continue with adapter update? (yes/no): ', resolve);
    });

    rl.close();

    if (answer.toLowerCase() !== 'yes') {
      console.log('\n❌ Update cancelled');
      process.exit(0);
    }
    console.log('');
  }

  console.log('🔄 Updating swap adapter...\n');

  const hash = await configFacet.write.updateSwapAdapter([newAdapterAddress]);
  console.log(`   Tx: ${hash}`);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  console.log('   ✅ Updated\n');

  const updatedAdapter = await configFacet.read.swapAdapter();

  console.log('╔════════════════════════════════════════╗');
  console.log('║          Update Success                ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Old Adapter: ${currentAdapter}`);
  console.log(`New Adapter: ${updatedAdapter}`);
  console.log(`Gas Used:    ${receipt.gasUsed}`);
  console.log('\n✅ Swap adapter updated successfully!');
}

main().catch((error) => {
  console.error('\n❌ Update failed:', error.message);
  process.exit(1);
});

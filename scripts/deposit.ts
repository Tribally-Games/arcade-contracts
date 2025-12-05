#!/usr/bin/env bun

import { parseEther, encodePacked, getContract, decodeEventLog, keccak256, toHex } from 'viem';
import { Command } from 'commander';
import { createClients, getDeployedAddress } from './utils';
import { NETWORK_CONFIGS, DEPOSITOR_ABI, formatTokenAmount } from './gateway-utils';

const GATEWAY_DEPOSIT_EVENT = {
  type: 'event',
  name: 'TriballyGatewayDeposit',
  inputs: [
    { type: 'address', name: 'user', indexed: true },
    { type: 'uint256', name: 'amount', indexed: false }
  ]
} as const;

const GATEWAY_DEPOSIT_EVENT_SIGNATURE = keccak256(toHex('TriballyGatewayDeposit(address,uint256)'));

function getDepositorName(target: string): string {
  if (target === 'base' || target === 'ronin') {
    return 'UniversalDexDepositor';
  }
  return 'DummyDexDepositor';
}

function getNetworkConfigKey(target: string): string {
  if (target === 'devnet1' || target === 'devnet2') {
    return 'local';
  }
  return target;
}

async function main() {
  const program = new Command();

  program
    .name('deposit')
    .description('Deposit native ETH/RON via DEX depositor')
    .argument('<target>', 'Target network (base|ronin|devnet1|devnet2)')
    .argument('<amount>', 'Amount to deposit in ETH/RON (e.g., 0.01)')
    .parse();

  const [target, amountStr] = program.args;

  const networkConfigKey = getNetworkConfigKey(target);
  const networkConfig = NETWORK_CONFIGS[networkConfigKey];

  if (!networkConfig) {
    console.error(`Invalid target: ${target}`);
    console.error('Valid targets: base, ronin, devnet1, devnet2');
    process.exit(1);
  }

  const { publicClient, walletClient, account } = createClients(target);

  const depositorName = getDepositorName(target);
  const depositorAddress = getDeployedAddress(target, depositorName);

  const amountIn = parseEther(amountStr);

  const swapPath = encodePacked(
    ['address', 'uint24', 'address'],
    [networkConfig.wethAddress, networkConfig.feeTier, networkConfig.usdcAddress]
  );

  const depositor = getContract({
    address: depositorAddress,
    abi: DEPOSITOR_ABI,
    client: { public: publicClient, wallet: walletClient },
  });

  console.log('╔════════════════════════════════════════╗');
  console.log('║           Deposit via DEX              ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Target:         ${target}`);
  console.log(`Account:        ${account.address}`);
  console.log(`Depositor:      ${depositorAddress}`);
  console.log(`Amount:         ${amountStr} ${networkConfig.nativeSymbol}`);
  console.log(`Swap Path:      ${swapPath}`);
  console.log('─────────────────────────────────────────');

  const balance = await publicClient.getBalance({ address: account.address });
  console.log(`\nBalance:        ${formatTokenAmount(balance, 18, networkConfig.nativeSymbol)}`);

  if (balance < amountIn) {
    console.error(`\nInsufficient balance. Have: ${formatTokenAmount(balance, 18)}, Need: ${amountStr}`);
    process.exit(1);
  }

  console.log('\nExecuting deposit...');

  const depositTx = await depositor.write.deposit(
    [account.address, '0x0000000000000000000000000000000000000000', amountIn, 0n, swapPath],
    { value: amountIn }
  );

  console.log(`Tx:             ${depositTx}`);

  const receipt = await publicClient.waitForTransactionReceipt({ hash: depositTx });

  const depositLog = receipt.logs.find(log => log.topics[0] === GATEWAY_DEPOSIT_EVENT_SIGNATURE);

  if (!depositLog) {
    throw new Error('TriballyGatewayDeposit event not found in transaction logs');
  }

  const decoded = decodeEventLog({
    abi: [GATEWAY_DEPOSIT_EVENT],
    data: depositLog.data,
    topics: depositLog.topics
  });

  const usdcDeposited = decoded.args.amount;

  console.log('\n╔════════════════════════════════════════╗');
  console.log('║           Deposit Complete             ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Gas Used:       ${receipt.gasUsed}`);
  console.log(`USDC Deposited: ${formatTokenAmount(usdcDeposited, 6, 'USDC')}`);
  console.log(`\nDeposit successful!`);
}

main().catch((error) => {
  console.error('\nDeposit failed:', error.message);
  if (error.cause) {
    console.error('Cause:', error.cause);
  }
  process.exit(1);
});

#!/usr/bin/env bun

import { getContract, decodeEventLog, keccak256, toHex, encodePacked } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { Command } from 'commander';
import { createClients, getDeployedAddress, loadGemforgeDeployments } from './utils';
import { DIAMOND_ABI, formatTokenAmount, parseTokenAmount } from './gateway-utils';

const GATEWAY_WITHDRAW_EVENT = {
  type: 'event',
  name: 'TriballyGatewayWithdraw',
  inputs: [
    { type: 'address', name: 'user', indexed: false },
    { type: 'uint256', name: 'amount', indexed: false }
  ]
} as const;

const GATEWAY_WITHDRAW_EVENT_SIGNATURE = keccak256(toHex('TriballyGatewayWithdraw(address,uint256)'));

async function main() {
  const program = new Command();

  program
    .name('withdraw')
    .description('Withdraw USDC from diamond proxy with authorized signature')
    .argument('<target>', 'Target network (base|ronin|devnet1|devnet2)')
    .argument('<user>', 'Recipient address')
    .argument('<amount>', 'Amount in USDC (e.g., 100.5)')
    .parse();

  const [target, user, amountStr] = program.args;

  const signerPrivateKey = process.env.SIGNER_PRIVATE_KEY;
  if (!signerPrivateKey) {
    console.error('SIGNER_PRIVATE_KEY environment variable is required');
    process.exit(1);
  }

  const { publicClient, walletClient, account } = createClients(target);

  const diamondAddress = getDeployedAddress(target, 'DiamondProxy');

  const signerAccount = privateKeyToAccount(signerPrivateKey as `0x${string}`);

  const deployments = loadGemforgeDeployments();
  const chainId = deployments[target]?.chainId;
  if (!chainId) {
    console.error(`Chain ID not found for target: ${target}`);
    process.exit(1);
  }

  const diamond = getContract({
    address: diamondAddress,
    abi: DIAMOND_ABI,
    client: { public: publicClient, wallet: walletClient },
  });

  console.log('╔════════════════════════════════════════╗');
  console.log('║           Withdraw USDC                ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Target:         ${target}`);
  console.log(`Sender:         ${account.address}`);
  console.log(`Recipient:      ${user}`);
  console.log(`Diamond:        ${diamondAddress}`);
  console.log(`Amount:         ${amountStr} USDC`);
  console.log(`Signer:         ${signerAccount.address}`);
  console.log('─────────────────────────────────────────');

  const contractSigner = await diamond.read.signer() as `0x${string}`;
  console.log(`\nContract Signer: ${contractSigner}`);

  if (contractSigner.toLowerCase() !== signerAccount.address.toLowerCase()) {
    console.error(`\nSigner mismatch!`);
    console.error(`Expected: ${contractSigner}`);
    console.error(`Got:      ${signerAccount.address}`);
    process.exit(1);
  }

  const poolBalance = await diamond.read.gatewayPoolBalance() as bigint;
  console.log(`Pool Balance:    ${formatTokenAmount(poolBalance, 6, 'USDC')}`);

  const amountWei = parseTokenAmount(amountStr, 6);

  if (poolBalance < amountWei) {
    console.error(`\nInsufficient pool balance.`);
    console.error(`Have: ${formatTokenAmount(poolBalance, 6, 'USDC')}`);
    console.error(`Need: ${amountStr} USDC`);
    process.exit(1);
  }

  const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

  const payload = encodePacked(
    ['address', 'uint256', 'uint256', 'uint256'],
    [user as `0x${string}`, amountWei, deadline, BigInt(chainId)]
  );

  const signature = await signerAccount.signMessage({
    message: { raw: keccak256(payload) }
  });

  console.log(`\nDeadline:        ${deadline} (${new Date(Number(deadline) * 1000).toISOString()})`);
  console.log(`\nExecuting withdrawal...`);

  const withdrawTx = await diamond.write.withdraw([
    user as `0x${string}`,
    amountWei,
    { signature, deadline }
  ]);

  console.log(`Tx:             ${withdrawTx}`);

  const receipt = await publicClient.waitForTransactionReceipt({ hash: withdrawTx });

  const withdrawLog = receipt.logs.find(log => log.topics[0] === GATEWAY_WITHDRAW_EVENT_SIGNATURE);

  if (!withdrawLog) {
    throw new Error('TriballyGatewayWithdraw event not found in transaction logs');
  }

  const decoded = decodeEventLog({
    abi: [GATEWAY_WITHDRAW_EVENT],
    data: withdrawLog.data,
    topics: withdrawLog.topics
  });

  const usdcWithdrawn = decoded.args.amount;

  console.log('\n╔════════════════════════════════════════╗');
  console.log('║         Withdrawal Complete            ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Gas Used:       ${receipt.gasUsed}`);
  console.log(`USDC Withdrawn: ${formatTokenAmount(usdcWithdrawn, 6, 'USDC')}`);
  console.log(`\nWithdrawal successful!`);
}

main().catch((error) => {
  console.error('\nWithdrawal failed:', error.message);
  if (error.cause) {
    console.error('Cause:', error.cause);
  }
  process.exit(1);
});

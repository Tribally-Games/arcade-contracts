#!/usr/bin/env bun

import { parseAbi, getContract, formatUnits } from 'viem';
import { createClients } from './utils';

const ADAPTER_ABI = parseAbi([
  'function swap(address,uint256,uint256,bytes) returns (uint256)',
  'function usdcToken() view returns (address)',
]);

const ERC20_ABI = parseAbi([
  'function approve(address,uint256) returns (bool)',
  'function balanceOf(address) view returns (uint256)',
  'function transfer(address,uint256) returns (bool)',
  'function decimals() view returns (uint8)',
  'function symbol() view returns (string)',
]);

function formatAmount(amount: bigint, decimals: number): string {
  const divisor = 10n ** BigInt(decimals);
  const whole = amount / divisor;
  const fraction = amount % divisor;
  const fractionStr = fraction.toString().padStart(decimals, '0');
  return `${whole}.${fractionStr.slice(0, 6)}`;
}

async function main() {
  const target = process.argv[2];
  const quoteOnly = process.argv.includes('--quote-only');

  if (!target) {
    console.error('Usage: bun test-dex-adapter.ts <ronin|base|local> [--quote-only]');
    console.error('');
    console.error('Required environment variables:');
    console.error('  DEX_ADAPTER       - Adapter contract address');
    console.error('  TOKEN_IN          - Input token address');
    console.error('  AMOUNT_IN         - Amount to swap (in token decimals)');
    console.error('  SWAP_PATH         - Encoded swap path');
    console.error('');
    console.error('Optional environment variables:');
    console.error('  MIN_USDC_OUT      - Minimum USDC expected (for real swaps)');
    process.exit(1);
  }

  const { publicClient, walletClient, account } = createClients(target);

  const adapterAddress = process.env.DEX_ADAPTER as `0x${string}`;
  const tokenIn = process.env.TOKEN_IN as `0x${string}`;
  const amountIn = BigInt(process.env.AMOUNT_IN!);
  const swapPath = process.env.SWAP_PATH as `0x${string}`;
  const minUsdcOut = process.env.MIN_USDC_OUT ? BigInt(process.env.MIN_USDC_OUT) : 0n;

  if (!adapterAddress || !tokenIn || !amountIn || !swapPath) {
    console.error('Missing required environment variables');
    console.error('Please set: DEX_ADAPTER, TOKEN_IN, AMOUNT_IN, SWAP_PATH');
    process.exit(1);
  }

  const adapter = getContract({
    address: adapterAddress,
    abi: ADAPTER_ABI,
    client: { public: publicClient, wallet: walletClient },
  });

  const token = getContract({
    address: tokenIn,
    abi: ERC20_ABI,
    client: { public: publicClient, wallet: walletClient },
  });

  const usdcToken = await adapter.read.usdcToken();
  const usdcContract = getContract({
    address: usdcToken,
    abi: ERC20_ABI,
    client: { public: publicClient },
  });

  const [tokenSymbol, tokenDecimals, usdcSymbol, usdcDecimals] = await Promise.all([
    token.read.symbol(),
    token.read.decimals(),
    usdcContract.read.symbol(),
    usdcContract.read.decimals(),
  ]);

  console.log('╔════════════════════════════════════════╗');
  console.log('║       DEX Adapter Test                 ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Network:        ${target.toUpperCase()}`);
  console.log(`Mode:           ${quoteOnly ? 'QUOTE (simulation)' : 'SWAP (real)'}`);
  console.log(`Account:        ${account.address}`);
  console.log(`Adapter:        ${adapterAddress}`);
  console.log(`Token In:       ${tokenIn} (${tokenSymbol})`);
  console.log(`Amount In:      ${amountIn} (${formatAmount(amountIn, tokenDecimals)} ${tokenSymbol})`);
  console.log(`USDC Token:     ${usdcToken} (${usdcSymbol})`);
  console.log(`Swap Path:      ${swapPath}`);
  if (minUsdcOut > 0n) {
    console.log(`Min USDC Out:   ${minUsdcOut} (${formatAmount(minUsdcOut, usdcDecimals)} ${usdcSymbol})`);
  }
  console.log('─────────────────────────────────────────');

  if (quoteOnly) {
    console.log('\n📊 Getting quote via eth_call simulation...\n');

    try {
      const quote = (await publicClient.readContract({
        address: adapterAddress,
        abi: ADAPTER_ABI,
        functionName: 'swap',
        args: [tokenIn, amountIn, 0n, swapPath],
      })) as bigint;

      const rate = Number(quote) / Number(amountIn);

      console.log('╔════════════════════════════════════════╗');
      console.log('║            Quote Results               ║');
      console.log('╚════════════════════════════════════════╝');
      console.log(`Estimated USDC: ${quote} (${formatAmount(quote, usdcDecimals)} ${usdcSymbol})`);
      console.log(`Exchange Rate:  ${rate.toFixed(6)} ${usdcSymbol}/${tokenSymbol}`);
      console.log('\n✅ Quote successful!');
    } catch (error: any) {
      console.error('\n❌ Quote failed:', error.message);
      if (error.cause) {
        console.error('Cause:', error.cause);
      }
      throw error;
    }

    return;
  }

  console.log('\n🔄 Executing real swap...\n');

  const balance = await token.read.balanceOf([account.address]);
  console.log(`1. Checking balance...`);
  console.log(`   Your ${tokenSymbol} balance: ${formatAmount(balance, tokenDecimals)}`);

  if (balance < amountIn) {
    throw new Error(`Insufficient balance. Have: ${balance}, Need: ${amountIn}`);
  }

  const usdcBefore = await usdcContract.read.balanceOf([account.address]);
  console.log(`   Your ${usdcSymbol} balance: ${formatAmount(usdcBefore, usdcDecimals)}\n`);

  console.log('2. Approving adapter...');
  const approveTx = await token.write.approve([adapterAddress, amountIn]);
  console.log(`   Tx: ${approveTx}`);
  await publicClient.waitForTransactionReceipt({ hash: approveTx });
  console.log('   ✅ Approved\n');

  console.log('3. Transferring tokens to adapter...');
  const transferTx = await token.write.transfer([adapterAddress, amountIn]);
  console.log(`   Tx: ${transferTx}`);
  await publicClient.waitForTransactionReceipt({ hash: transferTx });
  console.log('   ✅ Transferred\n');

  console.log('4. Executing swap...');
  const swapTx = await adapter.write.swap([tokenIn, amountIn, minUsdcOut, swapPath]);
  console.log(`   Tx: ${swapTx}`);
  const receipt = await publicClient.waitForTransactionReceipt({ hash: swapTx });
  console.log('   ✅ Swap completed\n');

  const usdcAfter = await usdcContract.read.balanceOf([account.address]);
  const usdcReceived = usdcAfter - usdcBefore;
  const rate = Number(usdcReceived) / Number(amountIn);

  console.log('╔════════════════════════════════════════╗');
  console.log('║            Swap Results                ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Gas Used:       ${receipt.gasUsed}`);
  console.log(`USDC Received:  ${usdcReceived} (${formatAmount(usdcReceived, usdcDecimals)} ${usdcSymbol})`);
  console.log(`Exchange Rate:  ${rate.toFixed(6)} ${usdcSymbol}/${tokenSymbol}`);
  console.log(`New Balance:    ${formatAmount(usdcAfter, usdcDecimals)} ${usdcSymbol}`);

  if (minUsdcOut > 0n && usdcReceived < minUsdcOut) {
    console.log('\n⚠️  WARNING: Received less than minimum!');
  } else {
    console.log('\n✅ Swap successful!');
  }
}

main().catch((error) => {
  console.error('\n❌ Test failed:', error.message);
  if (error.cause) {
    console.error('Cause:', error.cause);
  }
  process.exit(1);
});

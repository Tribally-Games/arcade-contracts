#!/usr/bin/env bun

import { keccak256, toHex } from 'viem';
import { Command } from 'commander';

async function main() {
  const program = new Command();

  program
    .name('decode-calculated-amount-out')
    .description('Decode CalculatedAmountOut error data')
    .argument('<hex-data>', 'Hex-encoded error data (with or without 0x prefix)')
    .parse();

  const [hexDataRaw] = program.args;

  const hexData = hexDataRaw.startsWith('0x') ? hexDataRaw : `0x${hexDataRaw}`;

  if (hexData.length < 10) {
    throw new Error('Invalid hex data: too short to contain error selector');
  }

  const selector = hexData.slice(0, 10);
  const expectedSelector = keccak256(toHex('CalculatedAmountOut(uint256)')).slice(0, 10);

  console.log('╔════════════════════════════════════════╗');
  console.log('║  CalculatedAmountOut Error Decoder    ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`Input:            ${hexData}`);
  console.log(`Selector:         ${selector}`);
  console.log(`Expected:         ${expectedSelector}`);
  console.log('─────────────────────────────────────────');

  if (selector !== expectedSelector) {
    throw new Error(`Selector mismatch! This is not a CalculatedAmountOut error.\nGot: ${selector}\nExpected: ${expectedSelector}`);
  }

  console.log('✅ Selector matches CalculatedAmountOut\n');

  const amountOutHex = '0x' + hexData.slice(10);
  const amountOut = BigInt(amountOutHex);

  console.log('╔════════════════════════════════════════╗');
  console.log('║           Decoded Result              ║');
  console.log('╚════════════════════════════════════════╝');
  console.log(`amountOut (raw):  ${amountOut}`);
  console.log(`amountOut (hex):  ${amountOutHex}`);

  const formatWithDecimals = (amount: bigint, decimals: number, symbol: string) => {
    const divisor = 10n ** BigInt(decimals);
    const whole = amount / divisor;
    const fraction = amount % divisor;
    const fractionStr = fraction.toString().padStart(decimals, '0');
    return `${whole}.${fractionStr} ${symbol}`;
  };

  console.log('\nFormatted values (common token decimals):');
  console.log(`  As USDC (6):    ${formatWithDecimals(amountOut, 6, 'USDC')}`);
  console.log(`  As WETH (18):   ${formatWithDecimals(amountOut, 18, 'WETH')}`);
  console.log(`  As RON (18):    ${formatWithDecimals(amountOut, 18, 'RON')}`);
}

main().catch((error) => {
  console.error('\n❌ Decoding failed:', error.message);
  process.exit(1);
});

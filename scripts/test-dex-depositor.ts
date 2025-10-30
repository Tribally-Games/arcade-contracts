#!/usr/bin/env bun

import { getContract, encodePacked, encodeFunctionData, decodeEventLog, keccak256, toHex } from 'viem';
import { Command } from 'commander';
import { createClients } from './utils';
import { NETWORK_CONFIGS, parseCalculatedAmountOut, DEPOSITOR_ABI } from './gateway-utils';
import IERC20Artifact from '../out/IERC20.sol/IERC20.json';
import IERC20MetadataArtifact from '../out/IERC20Metadata.sol/IERC20Metadata.json';

const ERC20_ABI = [...IERC20Artifact.abi, ...IERC20MetadataArtifact.abi];

const GATEWAY_DEPOSIT_EVENT = {
  type: 'event',
  name: 'TriballyGatewayDeposit',
  inputs: [
    { type: 'address', name: 'user', indexed: true },
    { type: 'uint256', name: 'amount', indexed: false }
  ]
} as const;

const GATEWAY_DEPOSIT_EVENT_SIGNATURE = keccak256(toHex('TriballyGatewayDeposit(address,uint256)'));

function formatAmount(amount: bigint, decimals: number): string {
  const divisor = 10n ** BigInt(decimals);
  const whole = amount / divisor;
  const fraction = amount % divisor;
  const fractionStr = fraction.toString().padStart(decimals, '0');
  return `${whole}.${fractionStr.slice(0, 6)}`;
}

async function main() {
  const program = new Command();

  program
    .name('test-dex-depositor')
    .description('Test DEX depositor deposits on different networks')
    .argument('<network>', 'Network to use (ronin|base|local)')
    .argument('<depositor-address>', 'DEX depositor contract address')
    .argument('<token-type>', 'Token type to deposit (ron|wron|usdc on Ronin, eth|weth|usdc on Base, token|usdc on local)')
    .argument('<amount-in>', 'Amount to deposit (in token decimals, e.g., 100000000000000000 for 0.1 tokens)')
    .option('-m, --min-usdc-out <amount>', 'Minimum USDC expected', '0')
    .option('-q, --quote', 'Get deposit quote without executing transaction', false)
    .parse();

  const [network, depositorAddressRaw, tokenType, amountInStr] = program.args;
  const options = program.opts();
  const minUsdcOut = BigInt(options.minUsdcOut);
  const amountIn = BigInt(amountInStr);
  const depositorAddress = depositorAddressRaw as `0x${string}`;
  const isQuoteMode = options.quote;

  if (!NETWORK_CONFIGS[network]) {
    console.error(`Invalid network: ${network}`);
    console.error('Valid networks: ronin, base, local');
    process.exit(1);
  }

  const networkConfig = NETWORK_CONFIGS[network];

  const tokenTypeLower = tokenType.toLowerCase();
  const validTokenTypes = network === 'ronin'
    ? ['ron', 'wron', 'usdc']
    : network === 'base'
    ? ['eth', 'weth', 'usdc']
    : ['token', 'usdc'];

  if (!validTokenTypes.includes(tokenTypeLower)) {
    console.error(`Invalid token type: ${tokenType}`);
    console.error(`Valid token types for ${network}: ${validTokenTypes.join(', ')}`);
    process.exit(1);
  }

  const isNative = tokenTypeLower === 'ron' || tokenTypeLower === 'eth';
  const isUsdc = tokenTypeLower === 'usdc';
  const tokenIn: `0x${string}` = isNative
    ? '0x0000000000000000000000000000000000000000'
    : isUsdc
    ? networkConfig.usdcAddress
    : networkConfig.wethAddress;
  const tokenSymbol = isNative
    ? networkConfig.nativeSymbol
    : isUsdc
    ? 'USDC'
    : networkConfig.wrappedSymbol;

  const { publicClient, walletClient, account } = createClients(network);

  const swapPath = isUsdc
    ? '0x'
    : encodePacked(
        ['address', 'uint24', 'address'],
        [networkConfig.wethAddress, networkConfig.feeTier, networkConfig.usdcAddress]
      );

  const depositor = getContract({
    address: depositorAddress,
    abi: DEPOSITOR_ABI,
    client: { public: publicClient, wallet: walletClient },
  });

  const token = isNative ? null : getContract({
    address: tokenIn,
    abi: ERC20_ABI,
    client: { public: publicClient, wallet: walletClient },
  });

  const usdcContract = getContract({
    address: networkConfig.usdcAddress,
    abi: ERC20_ABI,
    client: { public: publicClient },
  });

  const tokenDecimals = isNative ? 18 : isUsdc ? 6 : await token!.read.decimals();
  const [usdcSymbol, usdcDecimals] = await Promise.all([
    usdcContract.read.symbol(),
    usdcContract.read.decimals(),
  ]);

  console.log('╔════════════════════════════════════════╗');
  console.log(`║       DEX Depositor ${isQuoteMode ? 'Quote' : 'Deposit'} Test       ║`);
  console.log('╚════════════════════════════════════════╝');
  console.log(`Mode:           ${isQuoteMode ? 'QUOTE (simulation)' : 'DEPOSIT (execution)'}`);
  console.log(`Network:        ${network.toUpperCase()}`);
  console.log(`Account:        ${account.address}`);
  console.log(`Depositor:      ${depositorAddress}`);
  console.log(`Token In:       ${tokenIn} (${tokenSymbol})`);
  console.log(`Amount In:      ${amountIn} (${formatAmount(amountIn, tokenDecimals)} ${tokenSymbol})`);
  console.log(`USDC Token:     ${networkConfig.usdcAddress} (${usdcSymbol})`);
  console.log(`Swap Path:      ${swapPath}`);
  if (minUsdcOut > 0n) {
    console.log(`Min USDC Out:   ${minUsdcOut} (${formatAmount(minUsdcOut, usdcDecimals)} ${usdcSymbol})`);
  }
  console.log('─────────────────────────────────────────');

  console.log(`\n🔄 ${isQuoteMode ? 'Getting quote' : 'Executing deposit'}...\n`);

  const balance = isNative
    ? await publicClient.getBalance({ address: account.address })
    : await token!.read.balanceOf([account.address]);

  console.log(`1. Checking balances...`);
  console.log(`   Your ${tokenSymbol} balance: ${formatAmount(balance, tokenDecimals)}`);

  const usdcBefore = await usdcContract.read.balanceOf([account.address]);
  console.log(`   Your ${usdcSymbol} balance: ${formatAmount(usdcBefore, usdcDecimals)}\n`);

  if (balance < amountIn) {
    throw new Error(`Insufficient balance. Have: ${formatAmount(balance, tokenDecimals)} ${tokenSymbol}, Need: ${formatAmount(amountIn, tokenDecimals)} ${tokenSymbol}`);
  }

  if (isNative) {
    console.log(`2. Skipping approval (native token)...\n`);
  } else {
    console.log(`2. Approving depositor to spend ${formatAmount(amountIn, tokenDecimals)} ${tokenSymbol}...`);
    const allowance = await token!.read.allowance([account.address, depositorAddress]);
    if (allowance < amountIn) {
      const approveTx = await token!.write.approve([depositorAddress, amountIn]);
      console.log(`   Tx: ${approveTx}`);
      await publicClient.waitForTransactionReceipt({ hash: approveTx });
      console.log('   ✅ Approved\n');
    } else {
      console.log('   ✅ Already approved\n');
    }
  }

  let usdcReceived: bigint;
  let gasUsed: bigint | undefined;

  if (isQuoteMode) {
    console.log(`3. Getting quote (token in: ${tokenIn}, amount in: ${amountIn}, swap path: ${swapPath})...`);

    try {
      await publicClient.call({
        account: account.address,
        to: depositorAddress,
        value: isNative ? amountIn : undefined,
        data: encodeFunctionData({
          abi: DEPOSITOR_ABI,
          functionName: 'getQuote',
          args: [tokenIn, amountIn, swapPath],
        }),
      });
      throw new Error('Quote did not revert as expected');
    } catch (error: any) {
      usdcReceived = parseCalculatedAmountOut(error);
      console.log('   ✅ Quote received\n');
    }
  } else {
    console.log('3. Executing deposit...');
    const depositTx = await depositor.write.deposit(
      [account.address, tokenIn, amountIn, minUsdcOut, swapPath],
      isNative ? { value: amountIn } : undefined
    );
    console.log(`   Tx: ${depositTx}`);
    const receipt = await publicClient.waitForTransactionReceipt({ hash: depositTx });
    console.log('   ✅ Deposit completed\n');

    const depositLog = receipt.logs.find(log => log.topics[0] === GATEWAY_DEPOSIT_EVENT_SIGNATURE);
    if (!depositLog) {
      throw new Error('TriballyGatewayDeposit event not found in transaction logs');
    }

    const decoded = decodeEventLog({
      abi: [GATEWAY_DEPOSIT_EVENT],
      data: depositLog.data,
      topics: depositLog.topics
    });

    usdcReceived = decoded.args.amount;
    gasUsed = receipt.gasUsed;
  }

  const rate = Number(usdcReceived) / Number(amountIn);

  console.log('╔════════════════════════════════════════╗');
  console.log(`║            ${isQuoteMode ? 'Quote' : 'Deposit'} Results             ║`);
  console.log('╚════════════════════════════════════════╝');
  if (gasUsed !== undefined) {
    console.log(`Gas Used:       ${gasUsed}`);
  }
  console.log(`${isQuoteMode ? 'Expected USDC:' : 'USDC Deposited:'} ${usdcReceived} (${formatAmount(usdcReceived, usdcDecimals)} ${usdcSymbol})`);
  console.log(`Exchange Rate:  ${rate.toFixed(6)} ${usdcSymbol}/${tokenSymbol}`);

  if (minUsdcOut > 0n && usdcReceived < minUsdcOut) {
    console.log(`\n⚠️  WARNING: ${isQuoteMode ? 'Quote is' : 'Received'} less than minimum!`);
  } else {
    console.log(`\n✅ ${isQuoteMode ? 'Quote retrieved successfully!' : 'Deposit successful!'}`);
  }
}

main().catch((error) => {
  console.error('\n❌ Test failed:', error.message);
  if (error.cause) {
    console.error('Cause:', error.cause);
  }
  process.exit(1);
});

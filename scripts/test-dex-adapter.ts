#!/usr/bin/env bun

import { getContract, encodePacked, encodeFunctionData } from 'viem';
import { Command } from 'commander';
import { createClients } from './utils';
import { NETWORK_CONFIGS } from './gateway-utils';
import IDexSwapAdapterArtifact from '../out/IDexSwapAdapter.sol/IDexSwapAdapter.json';
import IERC20Artifact from '../out/IERC20.sol/IERC20.json';
import IERC20MetadataArtifact from '../out/IERC20Metadata.sol/IERC20Metadata.json';

const ADAPTER_ABI = IDexSwapAdapterArtifact.abi;
const ERC20_ABI = [...IERC20Artifact.abi, ...IERC20MetadataArtifact.abi];

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
    .name('test-dex-adapter')
    .description('Test DEX adapter swaps on different networks')
    .argument('<network>', 'Network to use (ronin|base|local)')
    .argument('<adapter-address>', 'DEX adapter contract address')
    .argument('<token-type>', 'Token type to swap (ron|wron on Ronin, eth|weth on Base, token on local)')
    .argument('<amount-in>', 'Amount to swap (in token decimals, e.g., 100000000000000000 for 0.1 tokens)')
    .option('-m, --min-usdc-out <amount>', 'Minimum USDC expected', '0')
    .option('-q, --quote', 'Get swap quote without executing transaction', false)
    .parse();

  const [network, adapterAddressRaw, tokenType, amountInStr] = program.args;
  const options = program.opts();
  const minUsdcOut = BigInt(options.minUsdcOut);
  const amountIn = BigInt(amountInStr);
  const adapterAddress = adapterAddressRaw as `0x${string}`;
  const isQuoteMode = options.quote;

  if (!NETWORK_CONFIGS[network]) {
    console.error(`Invalid network: ${network}`);
    console.error('Valid networks: ronin, base, local');
    process.exit(1);
  }

  const networkConfig = NETWORK_CONFIGS[network];

  const tokenTypeLower = tokenType.toLowerCase();
  const validTokenTypes = network === 'ronin'
    ? ['ron', 'wron']
    : network === 'base'
    ? ['eth', 'weth']
    : ['token'];

  if (!validTokenTypes.includes(tokenTypeLower)) {
    console.error(`Invalid token type: ${tokenType}`);
    console.error(`Valid token types for ${network}: ${validTokenTypes.join(', ')}`);
    process.exit(1);
  }

  const isNative = tokenTypeLower === 'ron' || tokenTypeLower === 'eth';
  const tokenIn: `0x${string}` = isNative ? '0x0000000000000000000000000000000000000000' : networkConfig.wethAddress;
  const tokenSymbol = isNative ? networkConfig.nativeSymbol : networkConfig.wrappedSymbol;

  const { publicClient, walletClient, account } = createClients(network);

  const swapPath = encodePacked(
    ['address', 'uint24', 'address'],
    [networkConfig.wethAddress, networkConfig.feeTier, networkConfig.usdcAddress]
  );

  const adapter = getContract({
    address: adapterAddress,
    abi: ADAPTER_ABI,
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

  const tokenDecimals = isNative ? 18 : await token!.read.decimals();
  const [usdcSymbol, usdcDecimals] = await Promise.all([
    usdcContract.read.symbol(),
    usdcContract.read.decimals(),
  ]);

  console.log('╔════════════════════════════════════════╗');
  console.log(`║       DEX Adapter ${isQuoteMode ? 'Quote' : 'Swap'} Test           ║`);
  console.log('╚════════════════════════════════════════╝');
  console.log(`Mode:           ${isQuoteMode ? 'QUOTE (simulation)' : 'SWAP (execution)'}`);
  console.log(`Network:        ${network.toUpperCase()}`);
  console.log(`Account:        ${account.address}`);
  console.log(`Adapter:        ${adapterAddress}`);
  console.log(`Token In:       ${tokenIn} (${tokenSymbol})`);
  console.log(`Amount In:      ${amountIn} (${formatAmount(amountIn, tokenDecimals)} ${tokenSymbol})`);
  console.log(`USDC Token:     ${networkConfig.usdcAddress} (${usdcSymbol})`);
  console.log(`Swap Path:      ${swapPath}`);
  if (minUsdcOut > 0n) {
    console.log(`Min USDC Out:   ${minUsdcOut} (${formatAmount(minUsdcOut, usdcDecimals)} ${usdcSymbol})`);
  }
  console.log('─────────────────────────────────────────');

  console.log(`\n🔄 ${isQuoteMode ? 'Getting quote' : 'Executing swap'}...\n`);

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
    console.log(`2. Approving adapter to spend ${formatAmount(amountIn, tokenDecimals)} ${tokenSymbol}...`);
    const allowance = await token!.read.allowance([account.address, adapterAddress]);
    if (allowance < amountIn) {
      const approveTx = await token!.write.approve([adapterAddress, amountIn]);
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
    console.log('3. Getting quote...');

    const { data } = await publicClient.call({
      account: account.address,
      to: adapterAddress,
      value: isNative ? amountIn : undefined,
      data: encodeFunctionData({
        abi: ADAPTER_ABI,
        functionName: 'getQuote',
        args: [tokenIn, amountIn, swapPath],
      }),
    });

    if (!data) {
      throw new Error('Quote failed - no data returned');
    }

    usdcReceived = BigInt(data);
    console.log('   ✅ Quote received\n');
  } else {
    console.log('3. Executing swap...');
    const swapTx = await adapter.write.swap(
      [tokenIn, amountIn, minUsdcOut, swapPath],
      isNative ? { value: amountIn } : undefined
    );
    console.log(`   Tx: ${swapTx}`);
    const receipt = await publicClient.waitForTransactionReceipt({ hash: swapTx });
    console.log('   ✅ Swap completed\n');

    const usdcAfter = await usdcContract.read.balanceOf([account.address]);
    usdcReceived = usdcAfter - usdcBefore;
    gasUsed = receipt.gasUsed;
  }

  const rate = Number(usdcReceived) / Number(amountIn);

  console.log('╔════════════════════════════════════════╗');
  console.log(`║            ${isQuoteMode ? 'Quote' : 'Swap'} Results               ║`);
  console.log('╚════════════════════════════════════════╝');
  if (gasUsed !== undefined) {
    console.log(`Gas Used:       ${gasUsed}`);
  }
  console.log(`${isQuoteMode ? 'Expected USDC:' : 'USDC Received:'} ${usdcReceived} (${formatAmount(usdcReceived, usdcDecimals)} ${usdcSymbol})`);
  console.log(`Exchange Rate:  ${rate.toFixed(6)} ${usdcSymbol}/${tokenSymbol}`);
  if (!isQuoteMode) {
    const usdcAfter = await usdcContract.read.balanceOf([account.address]);
    console.log(`New Balance:    ${formatAmount(usdcAfter, usdcDecimals)} ${usdcSymbol}`);
  }

  if (minUsdcOut > 0n && usdcReceived < minUsdcOut) {
    console.log(`\n⚠️  WARNING: ${isQuoteMode ? 'Quote is' : 'Received'} less than minimum!`);
  } else {
    console.log(`\n✅ ${isQuoteMode ? 'Quote retrieved successfully!' : 'Swap successful!'}`);
  }
}

main().catch((error) => {
  console.error('\n❌ Test failed:', error.message);
  if (error.cause) {
    console.error('Cause:', error.cause);
  }
  process.exit(1);
});

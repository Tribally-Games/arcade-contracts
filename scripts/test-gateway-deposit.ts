#!/usr/bin/env bun

import { getContract, encodeFunctionData, decodeAbiParameters } from 'viem';
import { Command } from 'commander';
import { createClients } from './utils';
import { DIAMOND_ABI, getTokenConfig, formatTokenAmount, isNativeToken, buildSwapPath } from './gateway-utils';
import IERC20Artifact from '../out/IERC20.sol/IERC20.json';
import IERC20MetadataArtifact from '../out/IERC20Metadata.sol/IERC20Metadata.json';

const ERC20_ABI = [...IERC20Artifact.abi, ...IERC20MetadataArtifact.abi];

async function main() {
  const program = new Command();

  program
    .name('test-gateway-deposit')
    .description('Test deposits and quotes through the Gateway')
    .argument('<network>', 'Network (ronin|base|local1|local2)')
    .argument('<diamond-address>', 'Diamond contract address')
    .argument('<token-type>', 'Token type: ron | wron | eth | weth | usdc')
    .argument('<amount>', 'Amount in token decimals')
    .option('-u, --user <address>', 'User address for deposit (default: deployer)')
    .option('-m, --min-usdc <amount>', 'Minimum USDC expected', '0')
    .option('-q, --quote', 'Get quote only (no transaction)', false)
    .option('-f, --fee <number>', 'Pool fee tier (default: 3000)', '3000')
    .parse();

  const [network, diamondAddressRaw, tokenType, amountStr] = program.args;
  const options = program.opts();

  if (!['ronin', 'base', 'local1', 'local2'].includes(network)) {
    console.error(`Invalid network: ${network}`);
    console.error('Valid networks: ronin, base, local1, local2');
    process.exit(1);
  }

  const diamondAddress = diamondAddressRaw as `0x${string}`;
  const amount = BigInt(amountStr);
  const minUsdcOut = BigInt(options.minUsdc);
  const isQuoteMode = options.quote;

  const { publicClient, walletClient, account } = createClients(network);

  const userAddress = (options.user as `0x${string}`) || account.address;

  const tokenConfig = getTokenConfig(network, tokenType);
  if (!tokenConfig) {
    console.error(`Invalid token type: ${tokenType} for network ${network}`);
    process.exit(1);
  }

  const tokenAddress = tokenConfig.address;
  const tokenSymbol = tokenConfig.symbol;
  const tokenDecimals = tokenConfig.decimals;
  const isNative = isNativeToken(tokenAddress);

  const gateway = getContract({
    address: diamondAddress,
    abi: DIAMOND_ABI,
    client: { public: publicClient, wallet: walletClient },
  });

  const usdcAddress = await gateway.read.usdcToken();
  const usdcContract = getContract({
    address: usdcAddress,
    abi: ERC20_ABI,
    client: { public: publicClient, wallet: walletClient },
  });

  const [usdcSymbol, usdcDecimals] = await Promise.all([
    usdcContract.read.symbol(),
    usdcContract.read.decimals(),
  ]);

  const isUSDC = tokenAddress === usdcAddress;
  const feeTier = parseInt(options.fee);
  const swapPath = isUSDC ? ('0x' as `0x${string}`) : buildSwapPath(tokenAddress, usdcAddress, feeTier);

  console.log('╔════════════════════════════════════════╗');
  console.log(`║       Gateway ${isQuoteMode ? 'Quote' : 'Deposit'} Test            ║`);
  console.log('╚════════════════════════════════════════╝');
  console.log(`Mode:           ${isQuoteMode ? 'QUOTE (simulation)' : 'DEPOSIT (execution)'}`);
  console.log(`Network:        ${network.toUpperCase()}`);
  console.log(`Diamond:        ${diamondAddress}`);
  console.log(`User:           ${userAddress}`);
  console.log(`Token In:       ${tokenSymbol} ${isNative ? '(native)' : ''}`);
  console.log(`Amount In:      ${formatTokenAmount(amount, tokenDecimals, tokenSymbol)}`);
  if (minUsdcOut > 0n) {
    console.log(`Min USDC Out:   ${formatTokenAmount(minUsdcOut, usdcDecimals, usdcSymbol)}`);
  }
  console.log('─────────────────────────────────────────');

  console.log(`\n🔄 ${isQuoteMode ? 'Getting quote' : 'Executing deposit'}...\n`);

  const balance = isNative
    ? await publicClient.getBalance({ address: userAddress })
    : await getContract({
        address: tokenAddress,
        abi: ERC20_ABI,
        client: { public: publicClient },
      }).read.balanceOf([userAddress]);

  const poolBefore = await gateway.read.gatewayPoolBalance();

  console.log(`1. Checking balances...`);
  console.log(`   Your ${tokenSymbol} balance: ${formatTokenAmount(balance, tokenDecimals, tokenSymbol)}`);
  console.log(`   Gateway pool balance: ${formatTokenAmount(poolBefore, usdcDecimals, usdcSymbol)}\n`);

  if (balance < amount) {
    throw new Error(`Insufficient balance. Have: ${formatTokenAmount(balance, tokenDecimals, tokenSymbol)}, Need: ${formatTokenAmount(amount, tokenDecimals, tokenSymbol)}`);
  }

  let usdcReceived: bigint;
  let gasUsed: bigint | undefined;

  if (isQuoteMode) {
    console.log('2. Simulating deposit to get quote...');

    const { data } = await publicClient.call({
      account: userAddress,
      to: diamondAddress,
      value: isNative ? amount : undefined,
      data: encodeFunctionData({
        abi: DIAMOND_ABI,
        functionName: 'calculateUsdc',
        args: [tokenAddress, amount, swapPath],
      }),
    });

    if (!data) {
      throw new Error('Quote simulation failed - no data returned');
    }

    usdcReceived = BigInt(data);
    console.log('   ✅ Quote received\n');
  } else {
    if (isNative) {
      console.log(`2. Skipping approval (native token)...\n`);
    } else if (tokenAddress === usdcAddress) {
      console.log(`2. Skipping approval (USDC direct deposit)...\n`);
    } else {
      const token = getContract({
        address: tokenAddress,
        abi: ERC20_ABI,
        client: { public: publicClient, wallet: walletClient },
      });

      console.log(`2. Approving Gateway to spend ${formatTokenAmount(amount, tokenDecimals, tokenSymbol)}...`);
      const allowance = await token.read.allowance([userAddress, diamondAddress]);

      if (allowance < amount) {
        const approveTx = await token.write.approve([diamondAddress, amount]);
        console.log(`   Tx: ${approveTx}`);
        await publicClient.waitForTransactionReceipt({ hash: approveTx });
        console.log('   ✅ Approved\n');
      } else {
        console.log('   ✅ Already approved\n');
      }
    }

    console.log('3. Executing deposit...');
    const depositTx = await gateway.write.deposit(
      [userAddress, tokenAddress, amount, minUsdcOut, swapPath],
      isNative ? { value: amount } : undefined
    );
    console.log(`   Tx: ${depositTx}`);
    const receipt = await publicClient.waitForTransactionReceipt({ hash: depositTx });
    console.log('   ✅ Deposit completed\n');

    const logs = receipt.logs;
    const depositLog = logs.find((log: any) =>
      log.topics[0] === '0x' + 'a' // TriballyGatewayDeposit event signature hash prefix
    );

    if (depositLog && depositLog.data) {
      try {
        const decoded = decodeAbiParameters(
          [{ type: 'uint256' }, { type: 'uint256' }],
          depositLog.data as `0x${string}`
        );
        usdcReceived = decoded[1] as bigint;
      } catch {
        const poolAfter = await gateway.read.gatewayPoolBalance();
        usdcReceived = poolAfter - poolBefore;
      }
    } else {
      const poolAfter = await gateway.read.gatewayPoolBalance();
      usdcReceived = poolAfter - poolBefore;
    }

    gasUsed = receipt.gasUsed;
  }

  const rate = Number(usdcReceived) / Number(amount);
  const poolAfter = isQuoteMode ? poolBefore : await gateway.read.gatewayPoolBalance();

  console.log('╔════════════════════════════════════════╗');
  console.log(`║            ${isQuoteMode ? 'Quote' : 'Deposit'} Results              ║`);
  console.log('╚════════════════════════════════════════╝');
  if (gasUsed !== undefined) {
    console.log(`Gas Used:       ${gasUsed}`);
  }
  console.log(`Deposited:      ${formatTokenAmount(amount, tokenDecimals, tokenSymbol)}`);
  console.log(`${isQuoteMode ? 'Expected USDC:' : 'USDC Received:'} ${formatTokenAmount(usdcReceived, usdcDecimals, usdcSymbol)}`);
  console.log(`Exchange Rate:  ${rate.toFixed(6)} ${usdcSymbol}/${tokenSymbol}`);
  console.log(`Gateway Pool:   ${formatTokenAmount(poolAfter, usdcDecimals, usdcSymbol)}`);

  if (minUsdcOut > 0n && usdcReceived < minUsdcOut) {
    console.log(`\n⚠️  WARNING: ${isQuoteMode ? 'Quote is' : 'Received'} less than minimum!`);
  } else {
    console.log(`\n✅ ${isQuoteMode ? 'Quote retrieved successfully!' : 'Deposit successful!'}`);
  }
}

main().catch((error) => {
  console.error('\n❌ Test failed:', error.message);
  process.exit(1);
});

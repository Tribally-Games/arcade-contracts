#!/usr/bin/env bun

import { readFileSync, writeFileSync } from 'fs';
import { createClients } from './utils';
import { DEX_ROUTERS, TOKEN_CONFIGS } from './gateway-utils';
import { type Hex } from 'viem';
import { deployWithCreate3, getPredictedAddress } from './create3-deploy';
import { join } from 'path';

const DEPOSITOR_SALT = '0x4445585f4445504f5349544f5200000000000000000000000000000000013aff' as Hex;
const DEPLOYMENTS_FILE = join(process.cwd(), 'gemforge.deployments.json');

const WETH_LIQUIDITY_AMOUNT = 100n * 10n ** 18n;
const USDC_LIQUIDITY_AMOUNT = 100n * 10n ** 6n;

async function addLiquidityToDummyDepositor(
  clients: ReturnType<typeof createClients>,
  depositorAddress: Hex,
  wethAddress: Hex,
  usdcAddress: Hex,
  _network: string
) {
  console.log('\n💧 Adding initial liquidity to DummyDexDepositor...');

  const erc20Artifact = JSON.parse(
    readFileSync(join(process.cwd(), 'out/TestERC20.sol/TestERC20.json'), 'utf-8')
  );
  const wethArtifact = JSON.parse(
    readFileSync(join(process.cwd(), 'out/MockWETH.sol/MockWETH.json'), 'utf-8')
  );
  const depositorArtifact = JSON.parse(
    readFileSync(join(process.cwd(), 'out/DummyDexDepositor.sol/DummyDexDepositor.json'), 'utf-8')
  );

  const reserveWETH = await clients.publicClient.readContract({
    address: depositorAddress,
    abi: depositorArtifact.abi,
    functionName: 'reserveWETH',
    args: [],
  }) as bigint;

  const reserveUSDC = await clients.publicClient.readContract({
    address: depositorAddress,
    abi: depositorArtifact.abi,
    functionName: 'reserveUSDC',
    args: [],
  }) as bigint;

  if (reserveWETH > 0n || reserveUSDC > 0n) {
    console.log(`Liquidity already exists (WETH: ${reserveWETH}, USDC: ${reserveUSDC})`);
    console.log('Skipping liquidity addition.');
    return;
  }

  const wethBalance = await clients.publicClient.readContract({
    address: wethAddress,
    abi: wethArtifact.abi,
    functionName: 'balanceOf',
    args: [clients.account.address],
  }) as bigint;

  const usdcBalance = await clients.publicClient.readContract({
    address: usdcAddress,
    abi: erc20Artifact.abi,
    functionName: 'balanceOf',
    args: [clients.account.address],
  }) as bigint;

  console.log(`WETH balance: ${wethBalance} (need ${WETH_LIQUIDITY_AMOUNT})`);
  console.log(`USDC balance: ${usdcBalance} (need ${USDC_LIQUIDITY_AMOUNT})`);

  if (wethBalance < WETH_LIQUIDITY_AMOUNT) {
    console.warn(`⚠️  Insufficient WETH balance. Skipping liquidity addition.`);
    return;
  }

  if (usdcBalance < USDC_LIQUIDITY_AMOUNT) {
    console.warn(`⚠️  Insufficient USDC balance. Skipping liquidity addition.`);
    return;
  }

  console.log(`Approving WETH...`);
  const approveWethHash = await clients.walletClient.writeContract({
    address: wethAddress,
    abi: wethArtifact.abi,
    functionName: 'approve',
    args: [depositorAddress, WETH_LIQUIDITY_AMOUNT],
    account: clients.account,
    chain: null,
  });
  await clients.publicClient.waitForTransactionReceipt({ hash: approveWethHash });
  console.log('✓ WETH approved');

  console.log(`Approving USDC...`);
  const approveUsdcHash = await clients.walletClient.writeContract({
    address: usdcAddress,
    abi: erc20Artifact.abi,
    functionName: 'approve',
    args: [depositorAddress, USDC_LIQUIDITY_AMOUNT],
    account: clients.account,
    chain: null,
  });
  await clients.publicClient.waitForTransactionReceipt({ hash: approveUsdcHash });
  console.log('✓ USDC approved');

  console.log(`Adding liquidity (100 WETH + 100 USDC)...`);
  const addLiquidityHash = await clients.walletClient.writeContract({
    address: depositorAddress,
    abi: depositorArtifact.abi,
    functionName: 'addLiquidity',
    args: [WETH_LIQUIDITY_AMOUNT, USDC_LIQUIDITY_AMOUNT],
    account: clients.account,
    chain: null,
  });
  await clients.publicClient.waitForTransactionReceipt({ hash: addLiquidityHash });
  console.log('✓ Liquidity added successfully');
  console.log('  Initial price: 1 WETH = 1 USDC');
}

async function main() {
  const target = process.env.GEMFORGE_DEPLOY_TARGET;

  if (!target) {
    console.error('GEMFORGE_DEPLOY_TARGET environment variable not set');
    process.exit(1);
  }

  console.log(`\nPost-deploy: Deploying DexDepositor for target: ${target}`);

  const network = target.includes('devnet') ? target : target;

  if (!['ronin', 'base', 'devnet1', 'devnet2'].includes(network)) {
    throw new Error(`Invalid network: ${network}. Valid networks: ronin, base, devnet1, devnet2`);
  }

  const depositorType = (network === 'devnet1' || network === 'devnet2') ? 'dummy' : 'universal';

  const clients = createClients(network);

  const deployments = JSON.parse(readFileSync(DEPLOYMENTS_FILE, 'utf-8'));

  const targetDeployments = deployments[target];
  if (!targetDeployments) {
    throw new Error(`No deployments found for target: ${target}`);
  }

  const diamondProxy = targetDeployments.contracts.find((c: any) => c.name === 'DiamondProxy');
  if (!diamondProxy) {
    throw new Error(`DiamondProxy not found in deployments for target: ${target}`);
  }

  const diamondProxyAddress = diamondProxy.onChain.address;
  console.log(`Diamond Proxy Address: ${diamondProxyAddress}`);

  let contractName: string;
  let contractPath: string;
  let constructorArgs: any[];
  let constructorTypes: string[];

  if (depositorType === 'dummy') {
    const wethAddress = TOKEN_CONFIGS[network]?.weth?.address;
    const usdcAddress = TOKEN_CONFIGS[network]?.usdc?.address;
    const ownerAddress = clients.account.address;

    if (!wethAddress) {
      throw new Error(`No default WETH address for ${network}`);
    }
    if (!usdcAddress) {
      throw new Error(`No default USDC address for ${network}`);
    }

    contractName = 'DummyDexDepositor';
    contractPath = 'DummyDexDepositor.sol';
    constructorArgs = [wethAddress, diamondProxyAddress, usdcAddress, ownerAddress];
    constructorTypes = ['address', 'address', 'address', 'address'];
  } else {
    const routerAddress =
      network === 'base' ? DEX_ROUTERS[network]?.uniswap : DEX_ROUTERS[network]?.katana;
    const usdcAddress = TOKEN_CONFIGS[network]?.usdc?.address;
    const ownerAddress = clients.account.address;

    if (!routerAddress) {
      throw new Error(`No default router address for ${network}`);
    }

    if (!usdcAddress) {
      throw new Error(`No default USDC address for ${network}`);
    }

    contractName = 'UniversalDexDepositor';
    contractPath = `${contractName}.sol`;
    constructorArgs = [routerAddress, diamondProxyAddress, usdcAddress, ownerAddress];
    constructorTypes = ['address', 'address', 'address', 'address'];
  }

  const predictedAddress = await getPredictedAddress(clients, clients.account.address, DEPOSITOR_SALT);
  console.log(`Predicted depositor address: ${predictedAddress}`);

  const code = await clients.publicClient.getCode({ address: predictedAddress });
  if (code && code !== '0x') {
    console.log(`\n${contractName} already deployed at: ${predictedAddress}`);
    console.log('Skipping deployment.');

    const existingDepositor = targetDeployments.contracts.find((c: any) => c.name === contractName);
    if (!existingDepositor) {
      console.log(`\nNote: ${contractName} not found in deployments file. Adding it now...`);
      const depositorEntry = {
        name: contractName,
        fullyQualifiedName: `${contractPath}:${contractName}`,
        sender: clients.account.address,
        txHash: '0x0',
        onChain: {
          address: predictedAddress,
          constructorArgs,
        },
      };
      targetDeployments.contracts.push(depositorEntry);
      writeFileSync(DEPLOYMENTS_FILE, JSON.stringify(deployments, null, 2));
      console.log(`✓ Updated ${DEPLOYMENTS_FILE} with existing ${contractName} deployment`);
    }
    return;
  }

  console.log(`\nDeploying ${contractName} with args:`, constructorArgs);

  const result = await deployWithCreate3(clients, {
    contractName,
    contractPath,
    constructorArgs,
    constructorTypes,
    salt: DEPOSITOR_SALT,
    verification: undefined,
  });

  console.log(`\n${contractName} deployed at: ${result.address}`);
  console.log(`Transaction hash: ${result.txHash}`);

  const depositorEntry = {
    name: contractName,
    fullyQualifiedName: `${contractPath}:${contractName}`,
    sender: clients.account.address,
    txHash: result.txHash,
    onChain: {
      address: result.address,
      constructorArgs,
    },
  };

  targetDeployments.contracts.push(depositorEntry);

  writeFileSync(DEPLOYMENTS_FILE, JSON.stringify(deployments, null, 2));
  console.log(`\nUpdated ${DEPLOYMENTS_FILE} with ${contractName} deployment`);

  if (depositorType === 'dummy') {
    const wethAddress = TOKEN_CONFIGS[network]?.weth?.address;
    const usdcAddress = TOKEN_CONFIGS[network]?.usdc?.address;

    if (wethAddress && usdcAddress) {
      try {
        await addLiquidityToDummyDepositor(
          clients,
          result.address as Hex,
          wethAddress as Hex,
          usdcAddress as Hex,
          network
        );
      } catch (error) {
        console.error('Failed to add liquidity:', error);
        console.log('Continuing despite liquidity addition failure...');
      }
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

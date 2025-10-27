import { getContract, encodeAbiParameters, parseAbiParameters, type Hex } from 'viem';
import { ClientSetup, type VerificationConfig } from './utils';
import {
  FACTORY_DEPLOYED_ADDRESS,
  FACTORY_ABI,
  FACTORY_SIGNED_RAW_TX,
  FACTORY_DEPLOYER_ADDRESS,
  FACTORY_GAS_LIMIT,
  FACTORY_GAS_PRICE,
} from './create3';
import { readFileSync } from 'fs';
import { join } from 'path';
import { spawn } from 'child_process';

export interface DeployConfig {
  contractName: string;
  contractPath: string;
  constructorArgs: any[];
  constructorTypes: string[];
  salt: Hex;
  verification?: VerificationConfig;
}

export interface DeployResult {
  address: Hex;
  alreadyDeployed: boolean;
  txHash?: Hex;
  gasUsed?: bigint;
  verified?: boolean;
  verificationError?: string;
}

export async function checkCreate3Factory(clients: ClientSetup): Promise<boolean> {
  const { publicClient } = clients;

  const factoryCode = await publicClient.getCode({
    address: FACTORY_DEPLOYED_ADDRESS,
  });

  return factoryCode !== undefined && factoryCode !== '0x';
}

export async function getPredictedAddress(
  clients: ClientSetup,
  deployer: Hex,
  salt: Hex
): Promise<Hex> {
  const { publicClient, walletClient } = clients;

  const create3Factory = getContract({
    address: FACTORY_DEPLOYED_ADDRESS,
    abi: FACTORY_ABI,
    client: { public: publicClient, wallet: walletClient },
  });

  return (await create3Factory.read.getDeployed([deployer, salt])) as Hex;
}

export async function isContractDeployed(clients: ClientSetup, address: Hex): Promise<boolean> {
  const { publicClient } = clients;

  const code = await publicClient.getCode({ address });
  return code !== undefined && code !== '0x';
}

export async function ensureCreate3Factory(clients: ClientSetup): Promise<void> {
  const { publicClient, walletClient, account } = clients;

  const factoryCode = await publicClient.getCode({
    address: FACTORY_DEPLOYED_ADDRESS,
  });

  if (factoryCode && factoryCode !== '0x') {
    console.log(`✓ CREATE3 Factory already deployed at ${FACTORY_DEPLOYED_ADDRESS}`);
    return;
  }

  console.log('\n📦 CREATE3 Factory not found, deploying...');
  console.log(`  Target address: ${FACTORY_DEPLOYED_ADDRESS}`);
  console.log(`  Factory deployer: ${FACTORY_DEPLOYER_ADDRESS}`);

  const deployerBalance = await publicClient.getBalance({
    address: FACTORY_DEPLOYER_ADDRESS,
  });

  const requiredBalance = FACTORY_GAS_LIMIT * FACTORY_GAS_PRICE;

  console.log(`  Deployer balance: ${deployerBalance} wei`);
  console.log(`  Required balance: ${requiredBalance} wei (0.036 ETH/RON)`);

  if (deployerBalance < requiredBalance) {
    const fundingNeeded = requiredBalance - deployerBalance;
    const fundingWithBuffer = fundingNeeded + (fundingNeeded / 10n);

    console.log(`  ⚠️  Insufficient balance, auto-funding deployer...`);
    console.log(`  Funding amount: ${fundingWithBuffer} wei (${fundingNeeded} + 10% buffer)`);

    const userBalance = await publicClient.getBalance({ address: account.address });

    if (userBalance < fundingWithBuffer) {
      throw new Error(
        `Insufficient balance to fund CREATE3 factory deployer.\n` +
          `  Your address: ${account.address}\n` +
          `  Your balance: ${userBalance} wei\n` +
          `  Funding needed: ${fundingWithBuffer} wei\n\n` +
          `Please add funds to your deployer wallet.`
      );
    }

    const fundTx = await walletClient.sendTransaction({
      to: FACTORY_DEPLOYER_ADDRESS,
      value: fundingWithBuffer,
      account,
    });

    console.log(`  Funding tx: ${fundTx}`);
    await publicClient.waitForTransactionReceipt({ hash: fundTx });
    console.log(`  ✓ Factory deployer funded successfully`);
  }

  try {
    const txHash = await publicClient.sendRawTransaction({
      serializedTransaction: FACTORY_SIGNED_RAW_TX as Hex,
    });

    console.log(`  Transaction: ${txHash}`);
    console.log('  Waiting for confirmation...');

    const receipt = await publicClient.waitForTransactionReceipt({
      hash: txHash,
      timeout: 60000,
    });

    const deployedCode = await publicClient.getCode({
      address: FACTORY_DEPLOYED_ADDRESS,
    });

    if (!deployedCode || deployedCode === '0x') {
      throw new Error('Factory deployment failed - no code at expected address');
    }

    console.log(`✓ CREATE3 Factory deployed successfully`);
    console.log(`  Gas used: ${receipt.gasUsed}`);
    console.log(`  Block: ${receipt.blockNumber}`);
  } catch (error: any) {
    if (error.message?.includes('already known') || error.message?.includes('nonce too low')) {
      console.log('✓ CREATE3 Factory already deployed (tx already mined)');
      return;
    }
    throw error;
  }
}

async function verifyContract(
  address: Hex,
  contractName: string,
  contractPath: string,
  constructorArgs: any[],
  constructorTypes: string[],
  verification: VerificationConfig
): Promise<{ success: boolean; error?: string }> {
  console.log('\n🔍 Verifying contract on block explorer...');

  const encodedArgs =
    constructorArgs.length > 0
      ? encodeAbiParameters(parseAbiParameters(constructorTypes.join(',')), constructorArgs)
      : ('0x' as Hex);

  const contractIdentifier = `src/adapters/${contractPath}:${contractName}`;

  const args = [
    'verify-contract',
    address,
    contractIdentifier,
    '--verifier-url',
    verification.apiUrl,
    '--etherscan-api-key',
    verification.apiKey,
  ];

  if (verification.verifier) {
    args.push('--verifier', verification.verifier);
  }

  if (encodedArgs !== '0x') {
    args.push('--constructor-args', encodedArgs);
  }

  if (verification.chainId) {
    args.push('--chain', verification.chainId.toString());
  }

  return new Promise((resolve) => {
    const process = spawn('forge', args, {
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let stdout = '';
    let stderr = '';

    process.stdout.on('data', (data) => {
      stdout += data.toString();
    });

    process.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    process.on('close', (code) => {
      const output = stdout + stderr;

      if (code === 0 || output.includes('already verified')) {
        console.log('✅ Contract verified successfully!');
        resolve({ success: true });
      } else {
        const errorMsg = output || `Verification failed with code ${code}`;
        console.log(`⚠️  Verification failed: ${errorMsg}`);
        resolve({ success: false, error: errorMsg });
      }
    });
  });
}

export async function deployWithCreate3(
  clients: ClientSetup,
  config: DeployConfig
): Promise<DeployResult> {
  const { publicClient, walletClient, account } = clients;

  await ensureCreate3Factory(clients);

  const predictedAddress = await getPredictedAddress(clients, account.address, config.salt);
  const alreadyDeployed = await isContractDeployed(clients, predictedAddress);

  let txHash: Hex | undefined;
  let gasUsed: bigint | undefined;

  if (!alreadyDeployed) {
    const artifactPath = join(
      process.cwd(),
      'out',
      config.contractPath,
      `${config.contractName}.json`
    );
    const artifact = JSON.parse(readFileSync(artifactPath, 'utf-8'));

    const constructorData =
      config.constructorArgs.length > 0
        ? encodeAbiParameters(
            parseAbiParameters(config.constructorTypes.join(',')),
            config.constructorArgs
          )
        : ('0x' as Hex);

    const deployData = `${artifact.bytecode.object}${
      constructorData === '0x' ? '' : constructorData.slice(2)
    }` as Hex;

    const create3Factory = getContract({
      address: FACTORY_DEPLOYED_ADDRESS,
      abi: FACTORY_ABI,
      client: { public: publicClient, wallet: walletClient },
    });

    txHash = await create3Factory.write.deploy([config.salt, deployData]);
    const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash });
    gasUsed = receipt.gasUsed;
  }

  let verified: boolean | undefined;
  let verificationError: string | undefined;

  if (config.verification) {
    const result = await verifyContract(
      predictedAddress,
      config.contractName,
      config.contractPath,
      config.constructorArgs,
      config.constructorTypes,
      config.verification
    );
    verified = result.success;
    verificationError = result.error;
  }

  return {
    address: predictedAddress,
    alreadyDeployed,
    txHash,
    gasUsed,
    verified,
    verificationError,
  };
}

export async function deployWithCreate3AndLog(
  clients: ClientSetup,
  config: DeployConfig,
  displayName: string
): Promise<DeployResult> {
  console.log(`\nDeploying ${displayName}...`);
  console.log(`  Salt: ${config.salt}`);

  const result = await deployWithCreate3(clients, config);

  if (result.alreadyDeployed) {
    console.log(`✓ ${displayName} already deployed at ${result.address}`);
  } else {
    console.log(`✓ ${displayName} deployed at ${result.address}`);
    console.log(`  Transaction: ${result.txHash}`);
    console.log(`  Gas used: ${result.gasUsed}`);
  }

  return result;
}

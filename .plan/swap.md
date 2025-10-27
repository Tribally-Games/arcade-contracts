# Multi-Token Deposit with DEX Adapter Pattern

## Overview

Add support for depositing multiple tokens (beyond USDC) with automatic swapping to USDC via pluggable DEX adapters.

**Supported DEXes:**
- **Katana DEX** (Ronin chain)
- **Uniswap V3** (Base chain)

**Architecture Flow:**
1. User deposits non-USDC token → Main Diamond contract
2. Main contract transfers token → DEX Adapter contract
3. Adapter executes swap on respective DEX
4. Adapter transfers USDC back → Main Diamond contract
5. Main contract updates balance & emits event

**Quote Flow (Frontend):**
- Frontend calls `swap()` or `calculateUsdc()` via `eth_call` (staticcall) to simulate and get quote
- No actual state changes occur, just returns expected USDC amount

---

## Phase 1: DEX Adapters + Testing ✅ COMPLETED

### Implemented Files

#### 1. scripts/utils.ts
Shared utilities for TypeScript scripts:
- `createClients(target, rpcUrl?)` - Create viem clients for network
- `loadWallet(target)` - Load wallet from gemforge config (mnemonic or private key)
- `getChainConfig(target)` - Get chain config for local/base/ronin
- `getRpcUrl(target, configRpcUrl?)` - Get RPC URL from config

**Networks supported:**
- `local` - Foundry local chain
- `base` - Base mainnet
- `ronin` - Ronin chain
- `baseFork` - Base fork

#### 2. scripts/create3.ts ✅ NEW
CREATE3 factory constants for deterministic deployment:
- `FACTORY_DEPLOYED_ADDRESS`: `0x24fCFA23F3b22c15070480766E3fE2fad3E813EA`
- `FACTORY_ABI`: Contract interface for deploy() and getDeployed()
- Copied from tribal-token repo for consistency

#### 3. scripts/create3-deploy.ts ✅ NEW
Reusable CREATE3 deployment utilities:
- `checkCreate3Factory()` - Verify factory exists
- `getPredictedAddress()` - Get deterministic address from salt
- `isContractDeployed()` - Check if contract already deployed
- `deployWithCreate3()` - Deploy contract via CREATE3
- `deployWithCreate3AndLog()` - Deploy with formatted logging

**Benefits:**
- Deterministic addresses across networks
- Idempotent deployments (safe to run multiple times)
- Reusable for other deployment scripts

#### 4. scripts/predeploy.ts (Updated) ✅
Now handles both test token deployment (local) and DEX adapter deployment (ronin/base):

**Network Configurations:**
```typescript
const ADAPTER_CONFIGS = {
  ronin: {
    routerAddress: '0x5f0acdd3ec767514ff1bf7e79949640bf94576bd',
    usdcAddress: '0x0b7007c13325c48911f73a2dad5fa5dcbf808adc',
    salt: '0x4b4154414e415f41444150544552...beef',
  },
  base: {
    routerAddress: '0x2626664c2603336E57B271c5C0b26F421741e481',
    usdcAddress: '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913',
    salt: '0x554e49535741505f41444150544552...ef',
  }
}
```

**Execution Flow:**
- Local: Deploy test tokens (existing behavior)
- Ronin: Deploy KatanaSwapAdapter via CREATE3
- Base: Deploy UniswapV3SwapAdapter via CREATE3
- Other: Skip predeploy

#### 5. src/interfaces/IDexSwapAdapter.sol
Common interface for all DEX adapters:
```solidity
interface IDexSwapAdapter {
    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bytes calldata path
    ) external returns (uint256 amountOut);

    function usdcToken() external view returns (address);
}
```

#### 6. src/interfaces/IKatanaRouter.sol
Katana AggregateRouter interface:
```solidity
interface IKatanaRouter {
    function execute(
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 deadline
    ) external payable;
}
```

#### 7. src/interfaces/IV3SwapRouter.sol
Uniswap V3 SwapRouter interface:
```solidity
interface IV3SwapRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}
```

#### 8. src/adapters/KatanaSwapAdapter.sol
DEX adapter for Ronin/Katana:
- Uses V3_SWAP_EXACT_IN command (0x00)
- Encodes inputs with recipient, amount, slippage protection
- Transfers USDC back to caller after swap
- Owner functions: `rescueTokens()`, `transferOwnership()`

**Constructor:**
```solidity
constructor(address _katanaRouter, address _usdcToken, address _owner)
```

**Swap flow:**
1. Record USDC balance before
2. Approve Katana router for input tokens
3. Encode V3_SWAP_EXACT_IN command with parameters
4. Execute via `katanaRouter.execute()`
5. Calculate USDC received
6. Transfer USDC to caller

#### 9. src/adapters/UniswapV3SwapAdapter.sol
DEX adapter for Base/Uniswap V3:
- Uses `exactInput()` for swaps
- Transfers USDC back to caller after swap
- Owner functions: `rescueTokens()`, `transferOwnership()`

**Constructor:**
```solidity
constructor(address _swapRouter, address _usdcToken, address _owner)
```

**Swap flow:**
1. Approve Uniswap router for input tokens
2. Create ExactInputParams struct
3. Execute via `swapRouter.exactInput()`
4. Transfer USDC to caller

#### 10. scripts/test-dex-adapter.ts
Comprehensive test script for DEX adapters:
- Quote mode: Simulate swap via eth_call (no transaction)
- Swap mode: Execute real swap on network
- Displays token info, balances, exchange rates
- Supports both Ronin (Katana) and Base (Uniswap)

**Usage:**
```bash
# Get quote (simulation)
DEX_ADAPTER=0x... TOKEN_IN=0x... AMOUNT_IN=1000000 SWAP_PATH=0x... \
  bun scripts/test-dex-adapter.ts ronin --quote-only

# Execute real swap
DEX_ADAPTER=0x... TOKEN_IN=0x... AMOUNT_IN=1000000 SWAP_PATH=0x... \
  bun scripts/test-dex-adapter.ts ronin

# With minimum USDC protection
DEX_ADAPTER=0x... TOKEN_IN=0x... AMOUNT_IN=1000000 SWAP_PATH=0x... MIN_USDC_OUT=950000 \
  bun scripts/test-dex-adapter.ts base
```

### Path Encoding Format

**Uniswap V3 / Katana path encoding:**
```
abi.encodePacked(tokenIn, uint24(fee), intermediateToken, uint24(fee), ..., USDC)
```

**Examples:**
- Single-hop: `abi.encodePacked(WETH, uint24(3000), USDC)`
- Multi-hop: `abi.encodePacked(DAI, uint24(500), WETH, uint24(3000), USDC)`

**Fee tiers:**
- 500 = 0.05%
- 3000 = 0.3%
- 10000 = 1%

### Build Verification

All contracts compile successfully:
```bash
forge build
```

---

## Phase 2: Diamond Integration 🔄 PENDING

### Storage Layer Updates

#### LibAppStorage.sol
Add fields to AppStorage struct:
```solidity
address swapAdapter;  // Active DEX adapter contract
mapping(address => bytes) supportedTokenSwapPaths;  // token → encoded path
```

### Error Definitions

#### LibErrors.sol
Add error types:
```solidity
error UnsupportedDepositToken(address token);
error InsufficientUsdcReceived(uint256 received, uint256 minimum);
error TokenAlreadySupported(address token);
error TokenNotSupported(address token);
error SwapFailed();
```

### Initialization Updates

#### InitDiamond.sol
Update to accept swapAdapter parameter:
```solidity
function init(
    address _govToken,
    address _usdcToken,
    address _signer,
    address _swapAdapter
) external {
    AppStorage storage s = LibAppStorage.diamondStorage();
    if (s.diamondInitialized) revert DiamondAlreadyInitialized();

    s.diamondInitialized = true;
    s.govToken = _govToken;
    s.usdcToken = _usdcToken;
    s.signer = _signer;
    s.swapAdapter = _swapAdapter;

    emit InitializeDiamond(msg.sender);
}
```

### ConfigFacet Updates

#### New Functions

**addSupportedToken(address _token, bytes calldata _swapPath)** - Owner only
- Validate `_token != usdcToken`
- Validate not already supported
- Store path: `s.supportedTokenSwapPaths[_token] = _swapPath`
- Approve adapter: `IERC20(_token).approve(s.swapAdapter, type(uint256).max)`
- Emit `SupportedTokenAdded(address indexed token, bytes swapPath)`

**removeSupportedToken(address _token)** - Owner only
- Validate supported
- Delete path: `delete s.supportedTokenSwapPaths[_token]`
- Reset approval: `IERC20(_token).approve(s.swapAdapter, 0)`
- Emit `SupportedTokenRemoved(address indexed token)`

**updateSwapAdapter(address _newAdapter)** - Owner only
- Store old adapter
- Update `s.swapAdapter = _newAdapter`
- For each supported token, re-approve new adapter
- Emit `SwapAdapterUpdated(address indexed oldAdapter, address indexed newAdapter)`

**Getters:**
```solidity
function getSupportedTokenSwapPath(address) external view returns (bytes memory);
function isSupportedToken(address) external view returns (bool);
function swapAdapter() external view returns (address);
```

#### New Events
```solidity
event SupportedTokenAdded(address indexed token, bytes swapPath);
event SupportedTokenRemoved(address indexed token);
event SwapAdapterUpdated(address indexed oldAdapter, address indexed newAdapter);
```

### GatewayFacet Updates

#### Update deposit() signature
```solidity
function deposit(
    address _user,
    address _token,
    uint256 _amount,
    uint256 _minUsdcAmount
) external {
    AppStorage storage s = LibAppStorage.diamondStorage();

    // Transfer token from user
    LibToken.transferFrom(_token, msg.sender, _amount);

    uint256 usdcAmount;

    if (_token == s.usdcToken) {
        // Direct USDC deposit
        usdcAmount = _amount;
    } else {
        // Swap to USDC
        bytes memory path = s.supportedTokenSwapPaths[_token];
        if (path.length == 0) revert UnsupportedDepositToken(_token);

        // Transfer to adapter
        LibToken.transferTo(_token, s.swapAdapter, _amount);

        // Execute swap (adapter returns USDC to this contract)
        usdcAmount = IDexSwapAdapter(s.swapAdapter).swap(
            _token,
            _amount,
            _minUsdcAmount,
            path
        );

        // Verify slippage protection
        if (usdcAmount < _minUsdcAmount) {
            revert InsufficientUsdcReceived(usdcAmount, _minUsdcAmount);
        }
    }

    // Update balance
    s.gatewayPoolBalance += usdcAmount;

    // Emit event
    emit TriballyGatewayDeposit(_user, _token, _amount, usdcAmount);
}
```

#### Add calculateUsdc() function
```solidity
function calculateUsdc(address _token, uint256 _amount)
    external
    returns (uint256)
{
    AppStorage storage s = LibAppStorage.diamondStorage();

    if (_token == s.usdcToken) return _amount;

    bytes memory path = s.supportedTokenSwapPaths[_token];
    if (path.length == 0) revert UnsupportedDepositToken(_token);

    // Frontend calls this via eth_call for simulation
    return IDexSwapAdapter(s.swapAdapter).swap(_token, _amount, 0, path);
}
```

#### Update event
```solidity
event TriballyGatewayDeposit(
    address indexed user,
    address indexed depositToken,
    uint256 depositAmount,
    uint256 usdcAmount
);
```

### Frontend Usage Example
```typescript
// Get quote via eth_call (simulation)
const quote = await publicClient.readContract({
  address: gatewayAddress,
  abi: gatewayAbi,
  functionName: 'calculateUsdc',
  args: [tokenAddress, amountIn]
});

// Execute deposit with slippage protection
const minUsdcAmount = (quote * 95n) / 100n; // 5% slippage tolerance
await walletClient.writeContract({
  address: gatewayAddress,
  abi: gatewayAbi,
  functionName: 'deposit',
  args: [userAddress, tokenAddress, amountIn, minUsdcAmount]
});
```

### Phase 2 Implementation Order

1. Update [src/libs/LibAppStorage.sol](src/libs/LibAppStorage.sol) - Add storage fields
2. Update [src/libs/LibErrors.sol](src/libs/LibErrors.sol) - Add errors
3. Update [src/init/InitDiamond.sol](src/init/InitDiamond.sol) - Add InitParams struct
4. Update [src/facets/ConfigFacet.sol](src/facets/ConfigFacet.sol) - Add token management functions
5. Update [src/facets/GatewayFacet.sol](src/facets/GatewayFacet.sol) - Update deposit() and add calculateUsdc()
6. Update deployment configs in gemforge.config.cjs
7. Run integration tests

---

## Deployment Strategy

### Phase 1: Adapter Deployment & Testing

**Ronin Network:**
1. Deploy `KatanaSwapAdapter(katanaRouter, usdcToken, owner)`
2. Test quote: `bun scripts/test-dex-adapter.ts ronin --quote-only`
3. Test real swap: `bun scripts/test-dex-adapter.ts ronin`
4. Verify USDC received correctly

**Base Network:**
1. Deploy `UniswapV3SwapAdapter(uniswapRouter, usdcToken, owner)`
2. Test quote: `bun scripts/test-dex-adapter.ts base --quote-only`
3. Test real swap: `bun scripts/test-dex-adapter.ts base`
4. Verify USDC received correctly

### Phase 2: Diamond Integration

**Update gemforge.config.cjs targets:**
```javascript
targets: {
  base: {
    initArgs: [
      "0xe13E40e8FdB815FBc4a1E2133AB5588C33BaC45d",  // govToken
      "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",  // usdcToken
      "0x000000000000000000000000000000000000dead",  // signer
      "0x..." // swapAdapter address from Phase 1
    ],
    // ... rest of config
  },
  ronin: {
    initArgs: [
      "0x...",  // govToken
      "0x...",  // usdcToken
      "0x...",  // signer
      "0x..."   // swapAdapter address from Phase 1
    ],
    // ... rest of config
  }
}
```

**Post-deployment configuration:**
```bash
# Add supported tokens via ConfigFacet
# Example: Add WETH with path to USDC
cast send $GATEWAY_ADDRESS \
  "addSupportedToken(address,bytes)" \
  $WETH_ADDRESS \
  $(cast abi-encode "f(address,uint24,address)" $WETH_ADDRESS 3000 $USDC_ADDRESS)
```

---

## Testing Checklist

### Phase 1: Adapter Testing
- [x] KatanaSwapAdapter compiles
- [x] UniswapV3SwapAdapter compiles
- [ ] Deploy KatanaSwapAdapter to Ronin testnet
- [ ] Test Katana quote (simulation)
- [ ] Test Katana real swap
- [ ] Deploy UniswapV3SwapAdapter to Base testnet
- [ ] Test Uniswap quote (simulation)
- [ ] Test Uniswap real swap

### Phase 2: Diamond Integration
- [ ] Update storage, errors, init
- [ ] Update ConfigFacet
- [ ] Update GatewayFacet
- [ ] Deploy updated Diamond
- [ ] Add supported tokens
- [ ] Test USDC deposit (no swap)
- [ ] Test ERC20 deposit with swap
- [ ] Test calculateUsdc() for quotes
- [ ] Test slippage protection
- [ ] Test with multiple tokens
- [ ] End-to-end integration test

---

## Contract Addresses

### Ronin Mainnet
- Katana Router: `TBD`
- USDC: `TBD`
- KatanaSwapAdapter: `TBD`

### Base Mainnet
- Uniswap V3 SwapRouter: `0x2626664c2603336E57B271c5C0b26F421741e481`
- USDC: `0x833589fcd6edb6e08f4c7c32d4f71b54bda02913`
- UniswapV3SwapAdapter: `TBD`

---

## Notes

- Frontend must call `calculateUsdc()` via `eth_call` for quotes before executing deposit
- Slippage tolerance is calculated frontend-side based on quote
- Each supported token needs its swap path configured via `addSupportedToken()`
- USDC deposits skip the swap entirely for gas efficiency
- Adapters are immutable after construction (router addresses cannot change)
- Owner can rescue stuck tokens via `rescueTokens()` in adapters

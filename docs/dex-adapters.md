# Testing DEX adapters

The adapter deploys automatically during the predeploy phase.

```bash
export DEPLOYER_PRIVATE_KEY=...
GEMFORGE_DEPLOY_TARGET=ronin bun scripts/predeploy.ts
```

**Important Addresses:**
- Katana Router: `0x5f0acdd3ec767514ff1bf7e79949640bf94576bd`
- USDC (Ronin): `0x0b7007c13325c48911f73a2dad5fa5dcbf808adc`
- WRON: `0xe514d9deb7966c8be0ca922de8a064264ea6bcd4`

## Execute Swap

Perform a token swap (requires WRON in your wallet):

```bash
# Swap 0.1 WRON → USDC
bun scripts/test-dex-adapter.ts ronin <ADAPTER_ADDRESS> 100000000000000000

# With minimum output protection (90 USDC minimum)
bun scripts/test-dex-adapter.ts ronin <ADAPTER_ADDRESS> 100000000000000000 --min-usdc-out 90000000
```

The script:
- Automatically encodes the swap path (WRON → 0.3% fee → USDC)
- Checks if adapter already has sufficient token balance
- Only transfers tokens if needed
- Executes the swap and displays results

## Networks

The script supports:
- **ronin**: WRON ↔ USDC (0.3% fee)
- **base**: WETH ↔ USDC (0.3% fee)
- **local**: Test tokens ↔ USDC (0.3% fee)

Token addresses and swap paths are hardcoded for each network.

## Swap Path Encoding

The swap path format for Uniswap V3 / Katana V3 is: `tokenIn, fee, tokenOut` (packed encoding, not standard ABI encoding).

**Fee Tiers:**
- `500` = 0.05%
- `3000` = 0.3% (most common)
- `10000` = 1%

**Packed encoding (used by the script):**
```typescript
import { encodePacked } from 'viem';

const path = encodePacked(
  ['address', 'uint24', 'address'],
  [tokenInAddress, 3000, tokenOutAddress]
);
```

**Multi-hop example (TokenA → WRON → USDC):**
```typescript
const path = encodePacked(
  ['address', 'uint24', 'address', 'uint24', 'address'],
  [tokenA, 3000, wronAddress, 3000, usdcAddress]
);
```

Note: This is different from standard ABI encoding - bytes are packed tightly without padding.


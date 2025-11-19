# Smart Contracts Architecture

## Overview

The Tribally Games Arcade smart contract system implements the **Diamond Standard (EIP-2535)** upgradeable proxy pattern, managed through Gemforge. This architecture enables a modular, upgradeable protocol with signature-based authorization and multi-token gateway functionality.

---

## Contract Inventory

### Main Protocol Contracts

#### DiamondProxy
- **Type**: Deployable (Main Entry Point)
- **Purpose**: EIP-2535 Diamond proxy serving as the single entry point for all protocol interactions
- **Auto-generated**: Yes (via Gemforge)
- **Key Feature**: Delegates calls to facets based on function selectors

#### Custom Facets

**ConfigFacet**
- **Purpose**: Administrative configuration management
- **Responsibilities**:
  - Manage authorized signer address
  - Manage governance token reference
  - Expose USDC token address
- **Access Control**: Admin-only functions

**GatewayFacet**
- **Purpose**: Token deposit and withdrawal gateway
- **Responsibilities**:
  - Accept USDC deposits from users
  - Process signature-authorized USDC withdrawals
  - Track internal pool balance
- **Security**: Reentrancy protected, signature-based withdrawals

**SigningFacet**
- **Purpose**: Signature payload generation helper
- **Responsibilities**:
  - Generate consistent signature payloads for off-chain signing

#### Core Diamond Facets

**DiamondCutFacet**
- **Purpose**: Protocol upgrade functionality
- **Responsibilities**:
  - Add, replace, or remove facet functions
  - Execute initialization functions during upgrades

**DiamondLoupeFacet**
- **Purpose**: Diamond introspection
- **Responsibilities**:
  - Query available facets and functions
  - Provide transparency into diamond structure

**OwnershipFacet**
- **Purpose**: Ownership management
- **Responsibilities**:
  - Transfer diamond ownership
  - Query current owner

#### Initialization

**InitDiamond**
- **Type**: Initializer Contract
- **Purpose**: One-time initialization of diamond storage
- **Execution**: Called once during initial diamond deployment

### Utility Contracts

#### DummyDexDepositor
- **Type**: Deployable DEX Adapter
- **Purpose**: Simple constant-product AMM for development and testing
- **Use Case**: Local development, testnet testing
- **Features**:
  - Internal WETH/USDC liquidity pool
  - Constant product formula (x * y = k)
  - Direct deposit to gateway after swap
- **Access Control**: Owner can add/remove liquidity

#### UniversalDexDepositor
- **Type**: Deployable DEX Adapter
- **Purpose**: Production DEX adapter supporting Uniswap V3 and Katana
- **Use Case**: Mainnet and production environments
- **Features**:
  - Routes swaps through Universal Router
  - Supports complex multi-hop swaps
  - Configurable swap deadline
  - Emergency token rescue functionality
- **Access Control**: Owner can configure parameters and rescue tokens
- **Security**: Reentrancy protected

### Supporting Components

#### Libraries (7)
- **LibAppStorage**: Diamond storage pattern implementation
- **LibAuth**: Signature verification and replay protection
- **LibToken**: Safe ERC20 token transfer operations
- **LibGovToken**: Governance token specific transfers
- **LibUsdcToken**: USDC token specific transfers
- **LibErrors**: Centralized custom error definitions
- **LibDiamondHelper**: Facet deployment and diamond cut utilities (auto-generated)

#### Interfaces (8)
- **IDiamondProxy**: Combined interface for all facet functions (auto-generated)
- **IDexDepositor**: Standard interface for DEX adapter contracts
- **IGatewayFacet**: Gateway facet interface
- **IUniversalRouter**: Universal Router interface for Uniswap V3/Katana
- **IDiamondCut**: Diamond upgrade interface
- **IDiamondLoupe**: Diamond introspection interface
- **IERC173**: Ownership standard interface
- **IERC165**: Interface detection standard

#### Abstract Contracts (2)
- **AccessControl**: Admin-only modifier using diamond ownership
- **ReentrancyGuard**: Reentrancy protection using diamond storage

#### Shared Definitions
- **Structs.sol**: Common data structures
  - AuthSignature: Signature with deadline
  - Transaction: Timestamp and amount record

#### Test/Mock Contracts
- **TestERC20**: Mock ERC20 with mint/burn for testing
- **MockWETH**: Wrapped ETH implementation for testing

---

## Contract Dependencies

### DiamondProxy Dependency Chain
```
DiamondProxy (EIP-2535 Proxy)
├── Diamond (diamond-2-hardhat base contract)
│   └── LibDiamond (core diamond logic)
├── DiamondCutFacet (upgrade functionality)
├── DiamondLoupeFacet (introspection)
├── OwnershipFacet (ownership management)
└── InitDiamond (one-time initialization)
    ├── LibAppStorage
    └── LibErrors
```

### ConfigFacet Dependency Chain
```
ConfigFacet
├── AccessControl (admin access control)
│   ├── LibDiamond (ownership verification)
│   └── LibErrors
├── LibAppStorage (diamond storage)
└── LibErrors (custom errors)
```

### GatewayFacet Dependency Chain
```
GatewayFacet
├── ReentrancyGuard (custom diamond storage version)
│   └── LibAppStorage
├── LibAuth (signature verification)
│   ├── OpenZeppelin SignatureChecker
│   ├── OpenZeppelin ECDSA
│   ├── LibErrors
│   └── LibAppStorage
├── LibUsdcToken (USDC transfers)
│   ├── LibToken (safe transfers)
│   │   ├── OpenZeppelin IERC20
│   │   └── OpenZeppelin SafeERC20
│   └── LibAppStorage
└── LibErrors
```

### DummyDexDepositor Dependency Chain
```
DummyDexDepositor
├── OpenZeppelin Ownable
├── OpenZeppelin SafeERC20
├── IDexDepositor (standard interface)
├── IGatewayFacet (gateway interface)
└── LibErrors
```

### UniversalDexDepositor Dependency Chain
```
UniversalDexDepositor
├── OpenZeppelin Ownable
├── OpenZeppelin ReentrancyGuard
├── OpenZeppelin SafeERC20
├── IDexDepositor (standard interface)
├── IUniversalRouter (Uniswap V3/Katana interface)
├── IGatewayFacet (gateway interface)
├── Commands (katana-operation-contracts)
└── LibErrors
```

### External Dependencies
- **OpenZeppelin Contracts**: Ownable, ReentrancyGuard, SafeERC20, IERC20, SignatureChecker, ECDSA
- **Diamond Standard (diamond-2-hardhat)**: Diamond, LibDiamond, core facets
- **Katana Operation Contracts**: Commands library, WETH (via Solmate)

---

## Roles and Ownership Architecture

### Role Hierarchy

The protocol implements a simple two-role model for the main diamond contract, plus independent ownership for utility contracts.

### Diamond Owner (Primary Admin)

**Implementation**: LibDiamond.contractOwner()

**Establishment**:
- Set during diamond deployment via constructor
- Stored in LibDiamond.DiamondStorage.contractOwner

**Powers**:
1. **Protocol Upgrades**: Execute diamond cuts to add, replace, or remove facets
2. **Configuration Management**:
   - Set the authorized signer address
   - Set the governance token address
3. **Ownership Transfer**: Transfer diamond ownership to a new address

**Access Pattern**:
- Functions check ownership via `LibDiamond.contractOwner() == msg.sender`
- Custom `isAdmin` modifier used in facets
- `LibDiamond.enforceIsContractOwner()` used in core facets

**Protected Operations**:
- `ConfigFacet.setSigner(address)` - Update authorized signer
- `ConfigFacet.setGovToken(address)` - Update governance token
- `DiamondCutFacet.diamondCut()` - Upgrade protocol
- `OwnershipFacet.transferOwnership(address)` - Transfer ownership

### Authorized Signer (Operational Role)

**Implementation**: LibAppStorage.diamondStorage().signer

**Establishment**:
- Set during diamond initialization via InitDiamond.init()
- Can be updated by diamond owner via ConfigFacet.setSigner()
- Stored in AppStorage.signer

**Powers**:
1. **Withdrawal Authorization**: Sign withdrawal requests for users
2. **Signature Control**: Each signature is single-use with deadline

**Signature Mechanism**:
- Uses ECDSA signatures with EIP-712 style message hashing
- Each signature includes:
  - Withdrawal data (user address, amount)
  - Deadline timestamp
  - Chain ID for replay protection across networks
- Replay protection via signature digest tracking

**Verification Process**:
1. Deadline validation (must not be expired)
2. EIP-712 style hash generation
3. ECDSA signature recovery and verification
4. Replay check (signature must not have been used before)
5. Mark signature as consumed

**Protected Operations**:
- `GatewayFacet.withdraw(address, uint256, AuthSignature)` - User withdrawals

### Depositor Owner (Independent Role)

**Implementation**: OpenZeppelin Ownable (separate from diamond)

**Establishment**:
- Set during depositor contract deployment
- Independent of diamond ownership
- Can be transferred via Ownable.transferOwnership()

**Powers (DummyDexDepositor)**:
- `addLiquidity(uint256, uint256)` - Add WETH/USDC to internal pool
- `removeLiquidity(uint256, uint256)` - Remove liquidity from pool

**Powers (UniversalDexDepositor)**:
- `setSwapDeadline(uint256)` - Configure swap deadline parameter
- `rescueTokens(address, uint256)` - Emergency token recovery

**Design Rationale**:
- Depositor contracts are utility adapters, not core protocol
- Independent ownership allows different operational control
- Separation of concerns between protocol governance and utility management

---

## Permission Flow Architecture

### Admin Configuration Flow

**Scenario**: Diamond owner updates protocol configuration

1. Owner calls `ConfigFacet.setSigner(newSigner)` or `ConfigFacet.setGovToken(newToken)`
2. `isAdmin` modifier checks `LibDiamond.contractOwner() == msg.sender`
3. If authorized, update stored in LibAppStorage
4. If unauthorized, revert with `CallerMustBeAdminError`

**Key Points**:
- Immediate effect, no timelock
- Single point of failure (centralized ownership)
- Consider multisig for production diamond owner

### Protocol Upgrade Flow

**Scenario**: Diamond owner upgrades protocol by adding/replacing/removing facets

1. Owner calls `DiamondCutFacet.diamondCut(facetCuts[], initAddress, initCalldata)`
2. `LibDiamond.enforceIsContractOwner()` validates caller
3. Process each facet cut (add/replace/remove function selectors)
4. Optionally execute initialization function on target contract
5. Emit DiamondCut event

**Key Points**:
- Can add new functionality without redeployment
- Can replace existing functions with updated logic
- Can remove deprecated functionality
- Maintains same proxy address through upgrades

### Withdrawal Authorization Flow

**Scenario**: User withdraws USDC from gateway with backend authorization

**Off-chain (Backend/Signer)**:
1. User requests withdrawal via backend API
2. Backend validates user eligibility and balance
3. Backend generates signature:
   - Payload: user address, amount, deadline, chain ID
   - Sign with authorized signer's private key
4. Backend returns signature to user

**On-chain (User)**:
1. User calls `GatewayFacet.withdraw(user, amount, signature)`
2. Reentrancy guard activated
3. Signature validation via LibAuth.assertValidSignature():
   - Check deadline not expired
   - Regenerate signature payload
   - Verify ECDSA signature matches authorized signer
   - Check signature not already consumed
   - Mark signature as consumed
4. Verify sufficient pool balance
5. Decrease internal pool balance tracking
6. Transfer USDC tokens to user
7. Emit TriballyGatewayWithdraw event

**Security Features**:
- Signatures expire after deadline (prevents stale authorizations)
- One-time use signatures (prevents replay attacks)
- Reentrancy protection
- Balance tracking separate from token holdings
- Chain ID in signature (prevents cross-chain replay)

### Direct Deposit Flow

**Scenario**: User deposits USDC directly to gateway

1. User approves DiamondProxy for USDC amount
2. User calls `GatewayFacet.deposit(user, amount)`
3. Reentrancy guard activated
4. Validate user address and amount
5. Transfer USDC from user to DiamondProxy via LibUsdcToken
6. Increase internal pool balance tracking
7. Emit TriballyGatewayDeposit event

**Key Points**:
- Simple, direct deposit
- No authorization required (deposits are permissionless)
- User specifies beneficiary address
- Pool balance tracked separately for withdrawal validation

### DEX-Mediated Deposit Flow

**Scenario**: User deposits non-USDC token, swap happens via DEX adapter

**For DummyDexDepositor (Internal AMM)**:
1. User approves DummyDexDepositor for input token amount
2. User calls `deposit(user, tokenIn, amountIn, minUsdcOut, path)`
3. If input token is USDC, transfer directly
4. If input token is not USDC:
   - Transfer input tokens to depositor
   - Execute swap via internal constant product pool
   - Verify output meets minimum
5. Approve DiamondProxy for USDC amount
6. Call `GatewayFacet.deposit(user, usdcAmount)`
7. Reset approval to zero
8. Emit TriballyGatewayDeposit event

**For UniversalDexDepositor (External Router)**:
1. User approves UniversalDexDepositor for input token amount
2. User calls `deposit(user, tokenIn, amountIn, minUsdcOut, path)`
3. Reentrancy guard activated
4. If input token is USDC, transfer directly
5. If input token is not USDC:
   - Transfer input tokens to depositor
   - Approve Universal Router for input amount
   - Encode swap command via Commands library
   - Execute swap via IUniversalRouter.execute()
   - Verify output meets minimum
6. Approve DiamondProxy for USDC amount
7. Call `GatewayFacet.deposit(user, usdcAmount)`
8. Reset approval to zero
9. Emit TriballyGatewayDeposit event

**Key Points**:
- Supports any token that can swap to USDC
- Slippage protection via minUsdcOut parameter
- Automatic approval management
- Final deposit always in USDC
- User specifies beneficiary address

---

## Security Architecture

### Diamond Standard Security Model

**Upgradeability**:
- Owner-controlled upgrades via DiamondCutFacet
- Can add, replace, or remove functionality
- Maintains single proxy address across upgrades
- No storage collisions via diamond storage pattern

**Risks**:
- Centralized upgrade authority (owner has full control)
- Malicious owner could replace facets with vulnerable code

**Mitigations**:
- Use multisig or DAO for diamond ownership in production
- Implement timelocks for diamond cuts
- Thorough testing and audits before upgrades

### Signature-Based Authorization

**Implementation**:
- Withdrawals require valid signature from authorized signer
- ECDSA signatures with EIP-712 style message hashing
- Signature payload includes: user, amount, deadline, chain ID

**Security Features**:
1. **Deadline Protection**: Signatures expire after specified timestamp
2. **Replay Protection**: Each signature can only be used once
3. **Chain Protection**: Chain ID prevents cross-chain replay attacks
4. **Separation of Concerns**: Signer authorizes, user executes

**Risks**:
- Compromised signer key enables unauthorized withdrawals
- Centralized authorization point

**Mitigations**:
- Secure key management for signer
- Backend validation before signing
- Monitoring for unusual withdrawal patterns
- Ability to rotate signer via ConfigFacet.setSigner()

### Reentrancy Protection

**Diamond Custom Implementation**:
- ReentrancyGuard abstract contract using diamond storage
- Prevents reentrancy across facets (shared storage)
- Uses LibAppStorage.diamondStorage().reentrancyStatus

**OpenZeppelin Implementation**:
- UniversalDexDepositor uses standard OpenZeppelin ReentrancyGuard
- Separate contract with independent storage

**Protected Operations**:
- `GatewayFacet.deposit()` - Prevents reentrant deposits
- `GatewayFacet.withdraw()` - Prevents reentrant withdrawals
- `UniversalDexDepositor.deposit()` - Prevents reentrant DEX deposits

### Safe Token Handling

**SafeERC20 Usage**:
- All token transfers use OpenZeppelin SafeERC20
- Handles non-standard ERC20 implementations
- Protects against missing return values

**Balance Tracking**:
- Gateway maintains internal balance counter (gatewayPoolBalance)
- Separate from actual token holdings
- Withdrawals checked against tracked balance
- Prevents accounting errors

### Access Control Summary

**Single Owner Model**:
- Diamond uses simple ownership via LibDiamond
- No role hierarchy (simpler but centralized)
- Clear authority for all admin operations

**Benefits**:
- Simple, easy to understand
- Lower gas costs than complex role systems
- Clear responsibility assignment

**Considerations**:
- Use multisig for production ownership
- Consider timelocks for critical operations
- Monitor owner actions closely

### Immutability Patterns

**Depositor Contracts**:
- Critical addresses (diamond, USDC, WETH, router) are immutable
- Set once during construction, cannot be changed
- Reduces attack surface for address manipulation

**Diamond Storage**:
- USDC and governance token addresses are mutable
- Only diamond owner can update via ConfigFacet
- Allows flexibility but requires trust in owner

---

## Deployment Architecture

### Gemforge Deployment Process

**Phase 1: Core Diamond Deployment**
1. Deploy core facets (DiamondCut, DiamondLoupe, Ownership)
2. Deploy custom facets (Config, Gateway, Signing)
3. Deploy InitDiamond initializer
4. Deploy DiamondProxy with:
   - Core facet addresses and function selectors
   - Owner address
   - InitDiamond address and initialization calldata
5. DiamondProxy constructor:
   - Stores facet mappings in LibDiamond storage
   - Calls InitDiamond.init() to initialize AppStorage
   - Transfers ownership to specified owner

**Phase 2: Utility Contract Deployment**
1. Deploy DummyDexDepositor (local/testnet only)
2. Deploy UniversalDexDepositor (testnet/mainnet)
3. Configure depositor parameters (owner, addresses)

**Phase 3: Post-Deployment Setup**
1. Fund DummyDexDepositor with WETH/USDC liquidity (if applicable)
2. Verify contracts on block explorer
3. Test deposit and withdrawal flows
4. Transfer ownership to production multisig (mainnet)

### Network-Specific Considerations

**Local Development**:
- Use DummyDexDepositor for simple testing
- Deploy mock tokens (TestERC20, MockWETH)
- Use test accounts as owner and signer

**Testnet**:
- Can use either DummyDexDepositor or UniversalDexDepositor
- Use testnet Universal Router addresses
- Use testnet tokens (USDC, WETH)

**Mainnet**:
- Use UniversalDexDepositor only
- Use production Universal Router addresses
- Use multisig for diamond ownership
- Use secure key management for signer
- Comprehensive audit before deployment

---

## Contract Addresses Storage

All deployed contract addresses are managed by Gemforge and stored in:
- `.gemforge/deployments.json` - Contract addresses per network
- Gemforge configuration tracks facet versions and addresses
- Addresses can be queried via DiamondLoupeFacet for transparency

---

## Summary

**Architecture Type**: Diamond Standard (EIP-2535) upgradeable proxy

**Total Deployable Contracts**: 10
- 1 Diamond proxy (main protocol)
- 6 Facets (3 core + 3 custom)
- 1 Initializer
- 2 DEX adapters (utility)

**Total Supporting Components**: 17
- 7 Libraries
- 8 Interfaces
- 2 Abstract contracts

**Access Control Model**: Two-role system
- Diamond Owner: Full administrative control
- Authorized Signer: Operational withdrawal authorization
- Depositor Owner: Independent utility contract management

**Key Security Features**:
- Diamond upgradeability with owner control
- Signature-based withdrawal authorization with replay protection
- Reentrancy guards (both custom and OpenZeppelin)
- SafeERC20 for all token transfers
- Immutable critical addresses in depositors
- Internal balance tracking separate from token holdings

**Design Philosophy**:
- Modularity via Diamond facets
- Security through signature verification and access control
- Flexibility via DEX adapters for multi-token deposits
- Upgradeability without proxy address changes
- Clean separation between core protocol and utility contracts

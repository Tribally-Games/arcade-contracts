# Changelog

All notable changes to this project will be documented in this file. See [commit-and-tag-version](https://github.com/absolute-version/commit-and-tag-version) for commit guidelines.

## [2.1.0](https://github.com/Tribally-Games/arcade-contracts/compare/v2.0.2...v2.1.0) (2025-12-03)


### Features

* add automatic liquidity provisioning to DummyDexDepositor in post-deploy ([6843b33](https://github.com/Tribally-Games/arcade-contracts/commit/6843b335670ba8823243e1ea7078f028230a1cba))
* add Multicall3 deployment to pre-deploy script ([6e69089](https://github.com/Tribally-Games/arcade-contracts/commit/6e6908924b05c3e6844b85e653338847efd8652c))
* add ownership transfer script and fix viem type errors ([e01262d](https://github.com/Tribally-Games/arcade-contracts/commit/e01262d9f11853ba2d999bfb5468e153df762ff9))


### Bug Fixes

* add msg.value validation to UniversalDexDepositor ([e5599e2](https://github.com/Tribally-Games/arcade-contracts/commit/e5599e23ce7ce744e2f1c0ae7652e5ae74e48fcf))

## [2.0.2](https://github.com/Tribally-Games/arcade-contracts/compare/v2.0.1...v2.0.2) (2025-10-30)


### Bug Fixes

* remove typo from README badge line ([38071f5](https://github.com/Tribally-Games/arcade-contracts/commit/38071f542e32a66eae8dbd53b60f162b5ee1c059))

## [2.0.1](https://github.com/Tribally-Games/arcade-contracts/compare/v2.0.0...v2.0.1) (2025-10-30)

## [2.0.0](https://github.com/Tribally-Games/arcade-contracts/compare/v1.3.2...v2.0.0) (2025-10-30)


### ⚠ BREAKING CHANGES

* Complete architectural refactoring of the gateway system

- Rename src/adapters → src/depositors with updated contract names
  - UniversalSwapAdapter → UniversalDexDepositor
  - DummyDexAdapter → DummyDexDepositor
  - IDexSwapAdapter → IDexDepositor

- Update depositor architecture
  - Depositors now orchestrate swaps and call diamond.deposit()
  - Diamond no longer knows about depositors (removed from storage/config)
  - Added 4-param constructor: (router, diamond, usdc, owner)
  - Implement USDC passthrough in deposit() and getQuote()
  - Add receive() function to prevent accidental ETH transfers

- Simplify GatewayFacet
  - Remove calculateUsdc() method entirely
  - Update deposit() to USDC-only: deposit(address user, uint256 amount)
  - Remove adapter tracking from AppStorage

- Update deployment flow
  - Remove adapter deployment from pre-deploy.ts
  - Add post-deploy.ts to deploy depositor after diamond
  - Use dedicated salt for depositor deployment
  - Check on-chain deployment status to skip if already deployed
  - Auto-update gemforge.deployments.json

- Rename and enhance scripts
  - deploy-adapter.ts → deploy-depositor.ts
  - test-dex-adapter.ts → test-dex-depositor.ts
  - Add USDC token type support to test-dex-depositor.ts
  - Extract deposited amount from GatewayFacet event logs
  - Update gateway-utils.ts with DEPOSITOR_ABI export

- Update all tests for new architecture
  - Create MockDiamond for depositor testing
  - Fix constructor calls with 4 parameters
  - Change swap() method calls to deposit(user, ...)
  - Remove adapter validation from ConfigTest
  - Update InitDiamond to 3-parameter signature

Tests: All 78 tests passing (47 depositor + 31 other)

* transform adapter pattern to depositor pattern with post-deploy architecture ([2244be2](https://github.com/Tribally-Games/arcade-contracts/commit/2244be2ae2e76f5e4b9d95f9e41d2d874d60e034))

## [1.3.2](https://github.com/Tribally-Games/arcade-contracts/compare/v1.3.1...v1.3.2) (2025-10-30)

## [1.3.1](https://github.com/Tribally-Games/arcade-contracts/compare/v1.3.0...v1.3.1) (2025-10-27)

## [1.3.0](https://github.com/Tribally-Games/arcade-contracts/compare/v1.2.0...v1.3.0) (2025-10-27)


### Features

* implement DEX adapters for multi-token deposits ([#3](https://github.com/Tribally-Games/arcade-contracts/issues/3)) ([44cec4f](https://github.com/Tribally-Games/arcade-contracts/commit/44cec4f74286e18b4798bb3745ab67d2d00493a9))

## [1.2.0](https://github.com/Tribally-Games/arcade-contracts/compare/v1.1.3...v1.2.0) (2025-10-19)


### Features

* add configurable token parameters and multi-token deployment ([b25443c](https://github.com/Tribally-Games/arcade-contracts/commit/b25443ce5a5e9edee28b1e5b8e3c014acc725656))

## [1.1.3](https://github.com/Tribally-Games/arcade-contracts/compare/v1.1.2...v1.1.3) (2025-10-19)

## [1.1.2](https://github.com/Tribally-Games/arcade-contracts/compare/v1.1.1...v1.1.2) (2025-10-19)

## [1.1.1](https://github.com/Tribally-Games/arcade-contracts/compare/v1.1.0...v1.1.1) (2025-10-18)

## 1.1.0 (2025-10-18)


### Bug Fixes

* use deterministic token address for local deployments ([4453433](https://github.com/Tribally-Games/arcade-contracts/commit/44534334839f77c7e9d7816c439b594cf3ad6273))

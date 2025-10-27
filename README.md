[![Build status](https://github.com/tribally-games/arcade-contracts/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Tribally-Games/arcade-contracts/actions/workflows/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/Tribally-Games/arcade-contracts/badge.svg?branch=main)](https://coveralls.io/github/Tribally-Games/arcade-contracts?branch=main)

# @tribally.games/arcade-contracts

Arcade smart contracts for [Tribally Games](https://tribally.games).

This is a [Diamond Standard](https://eips.ethereum.org/EIPS/eip-2535) upgradeable proxy contract managed using [Gemforge](https://gemforge.xyz/).

## On-chain addresses

* Base:
  * Arcade: [0xBC34eAfDB8B061D905e114B52D4Fb0bC46a02319](https://basescan.org/address/0xBC34eAfDB8B061D905e114B52D4Fb0bC46a02319)
  * Dex adapter: [0x630E7e9170fc4d7413801b752fc307eA97f8906F](https://basescan.org/address/0x630E7e9170fc4d7413801b752fc307eA97f8906F)

* Ronin:
  * Arcade: [0xADDab16d0feC4534899168470cC8853C9b3EBCFb](https://app.roninchain.com/address/0xADDab16d0feC4534899168470cC8853C9b3EBCFb)
  * DEX adapter: [0x630E7e9170fc4d7413801b752fc307eA97f8906F](https://app.roninchain.com/address/0x630E7e9170fc4d7413801b752fc307eA97f8906F)

## Usage guide

Install the NPM package:

* NPM: `npm install @tribally.games/arcade-contracts`
* Yarn: `yarn add @tribally.games/arcade-contracts`
* PNPM: `pnpm add @tribally.games/arcade-contracts`
* Bun: `bun add @tribally.games/arcade-contracts`

Use it within your code:

```js
const { abi, diamondProxy } = require('@tribally.games/arcade-contracts');

console.log(abi) // JSON ABI of the diamond proxy
console.log(diamondProxy.baseSepolia) // address of contracts on Base Sepolia
```

## Development guide

If you're working on this repo itself then these instructions are for you.

Ensure the following pre-requisites are installed

* [Node.js 20+](https://nodejs.org)
* [Bun](https://bun.sh/)
* [Foundry](https://github.com/foundry-rs/foundry/blob/master/README.md)

### Setup

```shell
$ foundryup
$ bun install
$ bun run bootstrap
```

Create `.env` and set the following within:

```
DEPLOYER_PRIVATE_KEY=<your deployment wallet private key>
BASESCAN_API_KEY=<your basescan api key>
```

### Usage

Run a local dev node in a separate terminal:

```shell
bun run devnet
```

To build the code:

```shell
$ bun run build
```

To run the tests:

```shell
$ bun run test
```

To deploy to the local target:

```shell
$ bun run dep local --new
```

To deploy to public networks:

* Base mainnet: `bun run dep base --new`

### Deploying to a new chain

Before deploying the Arcade contract to a new chain, you must first deploy the DEX adapter:

**Step 1: Deploy the DEX adapter**

```shell
bun run scripts/deploy-adapter.ts <network>
```

For example, to deploy to Base:
```shell
bun run scripts/deploy-adapter.ts base
```

**Step 2: Update gemforge.config.cjs**

Update the target's `initArgs` with the deployed adapter address (4th parameter):

```js
targets: {
  base: {
    initArgs: [
      "0x...", // govToken
      "0x...", // usdcToken
      "0x...", // signer
      "0x630E7e9170fc4d7413801b752fc307eA97f8906F", // swapAdapter <- UPDATE THIS
    ],
  }
}
```

**Step 3: Deploy the Arcade contract**

```shell
bun run dep <network> --new
```

The predeploy script will verify the adapter is deployed before proceeding. If the adapter is not deployed, you will see a clear error message with instructions.

### Verifying contracts

Once deployed you can verify contract source-codes on Basescan using:

* Base: `ETHERSCAN_API_KEY=... bun run verify base`

For verbose output simply add `-v`:

```shell
$ bun run build -v
$ bun run dep -v
```

### Publishing releases

To create a release:

```shell
$ bun run release        # patch version
$ bun run release:minor  # minor version
$ bun run release:major  # major version
```

## Documentation

For further docs on dev guides see [./docs](./docs) folder.


## License

AGPLv3 - see [LICENSE.md](LICENSE.md)

Tribally Games Arcade smart contracts
Copyright (C) 2025  [Tribally Games](https://tribally.games)

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
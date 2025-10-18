[![Build status](https://github.com/tribally-games/arcade-contracts/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Tribally-Games/arcade-contracts/actions/workflows/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/Tribally-Games/arcade-contracts/badge.svg?branch=main)](https://coveralls.io/github/Tribally-Games/arcade-contracts?branch=main)

# @tribally-games/arcade-contracts

Arcade smart contracts for [Tribally Games](https://tribally.games).

This is a [Diamond Standard](https://eips.ethereum.org/EIPS/eip-2535) upgradeable proxy contract managed using [Gemforge](https://gemforge.xyz/).

## On-chain addresses

* Base: [0x1224849B354a93C0BEe656E7779b584Ca2a03D5E](https://basescan.org/address/0x1224849B354a93C0BEe656E7779b584Ca2a03D5E)

## Usage guide

Install the NPM package:

* NPM: `npm install @tribally-games/arcade-contracts`
* Yarn: `yarn add @tribally-games/arcade-contracts`
* PNPM: `pnpm add @tribally-games/arcade-contracts`
* Bun: `bun add @tribally-games/arcade-contracts`

Use it within your code:

```js
const { abi, diamondProxy } = require('@tribally-games/arcade-contracts');

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
$ bun run dep local
```

To deploy to public networks:

* Base sepolia: `bun run dep base_sepolia`
* Base mainnet: `bun run dep base`

Once deployed you can verify contract source-codes on Basescan using:

* Base sepolia: `bun run verify base_sepolia`
* Base: `bun run verify base`

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
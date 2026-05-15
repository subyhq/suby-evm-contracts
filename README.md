# Suby.fi Protocol Contracts

Smart contracts powering the Suby.fi payment & settlement infrastructure. 

## Contracts

### `SubyPayment`

Atomic split-payment contract. The caller pre-approves the contract for the `tokenAddress`
(or sends `msg.value` for native payments), then calls
`payment(paymentId, token, splitData)` / `paymentNative(paymentId, splitData)` which
fan-outs the funds to all `recipient` addresses in a single transaction. Used by Suby for
direct same-chain settlements and as the destination call of LI.FI cross-chain quotes.

See: <https://documentation.suby.fi/docs/payment/stablecoins.md>

#### Deployments

| Chain     | Address                                                                                                                   | Tokens supported   |
| --------- | ------------------------------------------------------------------------------------------------------------------------- | ------------------ |
| Ethereum  | [`0xb331dc9b1b140c4af40ae8abe4e1d8a1529e5bbe`](https://etherscan.io/address/0xb331dc9b1b140c4af40ae8abe4e1d8a1529e5bbe)    | USDC, USDT, ETH    |
| Base      | [`0x8b8f73282c06f1c170101f228618b76eefd02550`](https://basescan.org/address/0x8b8f73282c06f1c170101f228618b76eefd02550)    | USDC, ETH          |
| Arbitrum  | [`0x997cd72dc8b25a5cdc1dbe34fa3fa0f1600124e1`](https://arbiscan.io/address/0x997cd72dc8b25a5cdc1dbe34fa3fa0f1600124e1)     | USDC, ETH          |
| BNB Chain | [`0x6cf4f2d9a328180fccc312c6c75fe9e0cea4d631`](https://bscscan.com/address/0x6cf4f2d9a328180fccc312c6c75fe9e0cea4d631)     | USDC, USDT, BNB    |
| Polygon   | [`0x272a3f2C6e60ca6AB7d543cc2820a7353C167772`](https://polygonscan.com/address/0x272a3f2C6e60ca6AB7d543cc2820a7353C167772) | USDC, USDT, POL    |
| Monad     | [`0x272a3f2C6e60ca6AB7d543cc2820a7353C167772`](https://monadscan.com/address/0x272a3f2C6e60ca6AB7d543cc2820a7353C167772)   | USDC, USDT, MON    |
| Solana    | Anchor program — see documentation                                                                                        | USDC, USDT, SOL    |

### `SubyMerchantVault`

Per-merchant escrow on Base holding USDC / EURC. ERC-20 deposits are plain transfers
(no `deposit()` function — the vault address is shared with the PFI and receives onramp
funds directly). Withdrawable balance = `balanceOf(token) - holdOf[token]`.

Roles:
- **Merchant** (immutable) — calls `withdraw(token, to, amount)` up to `availableToWithdraw`.
- **Operator** (resolved dynamically from the factory) — calls `hold` / `release` /
  `clawback` (to the factory `feeWallet`) / `rescue` (non-supported tokens only).

Every state-changing call emits an event (`Held`, `Released`, `Clawback`, `Withdrawn`, `Rescued`).

### `SubyMerchantVaultFactory`

CREATE2 deployer for `SubyMerchantVault`s on Base. The address returned by
`predictVault(salt, merchant)` is stable across networks for a given
`(factory, salt, merchant, USDC, EURC)` tuple — Suby pre-computes it and shares it with
the PFI **before** the contract exists. The vault is deployed lazily on the merchant's
first onramp via `deployVault(salt, merchant)` (operator-gated).

The factory also stores the `operator` and `feeWallet` addresses (owner-settable),
which every vault reads at runtime — rotating either takes a single factory transaction.

### `SubyRelayer`

USDC-only Base contract receiving bridges from Solana → EVM. The Suby operator calls
`executePayment(paymentId, splitData)`, which approves `SubyPayment` and forwards the
funds with the canonical merchant / fee-wallet / referrer split. Idempotent on `paymentId`.

## Setup

```sh
cp .env.example .env
forge install
```

## Tests

```sh
forge test -vvv
```

## Deployment

Each contract has a dedicated Foundry script under `scripts/deploy/`. Required env vars
are documented at the top of each `.s.sol` file. Example for the vault factory on Base:

```sh
forge script scripts/deploy/SubyMerchantVaultFactory.s.sol:DeploySubyMerchantVaultFactory \
  --rpc-url $RPC_BASE --broadcast --verify
```

## Resources

- Suby docs — <https://documentation.suby.fi>
- Stablecoin payment reference — <https://documentation.suby.fi/docs/payment/stablecoins.md>

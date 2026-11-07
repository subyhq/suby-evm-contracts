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
| Arc       | [`0xE1ac50e0CeCe63C24Ab24311Be5a6b8eb67bFC2f`](https://arc.etherscan.io/address/0xE1ac50e0CeCe63C24Ab24311Be5a6b8eb67bFC2f) | USDC, EURC         |
| Solana    | Anchor program — see documentation                                                                                        | USDC, USDT, SOL    |

Testnet:

| Chain        | Address                                                                                                                         | Tokens supported |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| Base Sepolia | [`0xA24d25d4FD4402a21dC237E605cd3130d7AF77cd`](https://sepolia.basescan.org/address/0xA24d25d4FD4402a21dC237E605cd3130d7AF77cd) | USDC, ETH        |

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

Contract receiving bridges from Solana → EVM. The Suby operator calls
`executePayment(paymentId, token, total, splitData)`, which approves `SubyPayment` and forwards
the funds with the canonical merchant / fee-wallet / referrer split. Idempotent on `paymentId`.

#### Deployments

| Chain   | Address                                                                                                                   | Tokens supported |
| ------- | ------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| Base    | [`0x1b5cC410042aE2A045ee1b135d46BC7568c0cD61`](https://basescan.org/address/0x1b5cc410042ae2a045ee1b135d46bc7568c0cd61)    | USDC, ETH        |
| Polygon | [`0xE1ac50e0CeCe63C24Ab24311Be5a6b8eb67bFC2f`](https://polygonscan.com/address/0xe1ac50e0cece63c24ab24311be5a6b8eb67bfc2f) | USDC, USDT, POL  |

### `SubySettlement`

Fan-out of a **pooled** stablecoin delivery (USDC / EURC on Base) to N merchant wallets in one
operator transaction. Used by the `STRIPE_MOR` model, where Suby collects card payments on its
own acquirer balance, converts a whole batch at once, and the ramp delivers **one amount to one
address** — this contract. Declared as the conversion beneficiary, so its address must reach the
PFI before the first batch.

#### Deployments

| Chain | Address                                                                                                                 | Tokens supported |
| ----- | ----------------------------------------------------------------------------------------------------------------------- | ---------------- |
| Base  | [`0x99c9c5C918fc397Ff20Da5b1686E24ee8249A99E`](https://basescan.org/address/0x99c9c5c918fc397ff20da5b1686e24ee8249a99e) | USDC, EURC       |

> An earlier build was deployed at
> [`0xcb6c14…139f`](https://basescan.org/address/0xcb6c14af9afec09a3c58c32aeda914f232d1139f) and is
> **superseded** — same behaviour, but it is not the address to declare anywhere. It holds no funds.

```solidity
distribute(address token, address[] recipients, uint256[] amounts, bytes32 batchId)  // operator
rescue(address token, address to)                                                    // owner
rescueNative(address to)                                                             // owner
```

An ERC-20 transfer runs no code on the recipient, so the contract **cannot** split on arrival: it
holds the delivery until the operator calls `distribute`. That window is minutes and is watched
off-chain. It is a conduit, not a vault — nothing is meant to rest here between batches, but the
guarantee is operational, not enforced on-chain (see below).

Properties that matter:

- **`batchId` is single-use.** A replay reverts instead of paying twice. An operator who does not
  know whether their transaction landed can safely re-broadcast — on-chain a double payment is
  irreversible.
- **Amounts come from the ledger, never from the balance.** The balance is read only to *refuse*
  an underfunded batch, never to *decide* who gets what. Splitting "whatever arrived" pro rata
  would invent an allocation the books do not know.
- **No "balance ends at zero" invariant.** Anyone can push 1 wei to the address, so asserting an
  empty balance would hand a griefer a permanent, free block on every batch. Leftovers and
  unmatched arrivals leave through `rescue`.
- **A failed payout does not revert the batch.** One frozen or blacklisted merchant address would
  otherwise hold up everyone else in the chunk. Failures surface as `PayoutFailed` and are retried
  under a **new** `batchId` covering the unsettled entries only — re-sending to a merchant already
  paid is not a retry, it is a second payment.
- **Underfunding does revert the whole batch.** A short arrival affects every recipient, not one.
- **Chunking:** ~29k gas per fresh recipient, so a batch too large for one block is split across
  several calls, each with its own `batchId`. Chunk size is a backend setting — there is
  deliberately no cap baked into the contract, since one that turned out too low could not be
  fixed.

Roles: `owner` holds `setOperator` / `pause` / `rescue`; `operator` is the backend signer
(`RELAYER_OPERATOR_PRIVATE_KEY`) and the only caller of `distribute` — **not** a DFNS key, since
DFNS custodies the *merchant* wallets, i.e. the destinations. `rescue` stays callable while paused:
pausing exists to stop payouts during an incident, and the recovery path must survive it.

> **Residual risk, stated rather than hidden.** A compromised operator key can direct whatever the
> contract currently holds to any address. There is no on-chain allowlist of merchant wallets —
> maintaining one would be a registry in its own right, and the wallets are Suby-custodied anyway.
> What bounds the damage is that the holding window is minutes.
>
> On the Base deployment `owner` and `operator` are the **same EOA**
> (`0x8b01…1CB8`, also the relayer's), so there is no hot/cold separation: that key can both pay
> out and sweep the full balance, and a compromise cannot be revoked because `setOperator` sits
> behind it. Splitting `owner` onto a multisig requires a redeploy — the roles are settable but
> the initial owner is not recoverable if its key is lost. Deliberate call, recorded here so the
> next reader does not assume the separation the design describes.

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

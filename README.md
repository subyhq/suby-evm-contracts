# Suby.fi Protocol Contracts

Smart contracts powering the Suby.fi payment & settlement infrastructure.
Docs: <https://documentation.suby.fi> · [Stablecoin payments](https://documentation.suby.fi/docs/payment/stablecoins.md)

## Contracts

| Contract                   | Role                                                                                                    |
| -------------------------- | ------------------------------------------------------------------------------------------------------- |
| `SubyPayment`              | Atomic split payment (ERC-20 or native) to N recipients. Used for same-chain settlement and as the LI.FI destination call. |
| `SubyMerchantVault`        | Per-merchant USDC / EURC escrow on Base. Merchant withdraws `balance - hold`; operator can `hold` / `release` / `clawback` / `rescue`. |
| `SubyMerchantVaultFactory` | CREATE2 deployer for vaults. `predictVault(salt, merchant)` gives the address before deployment; stores the `operator` and `feeWallet` every vault reads. |
| `SubyRelayer`              | Receives Solana → EVM bridges; the operator calls `executePayment`, which forwards through `SubyPayment`. Idempotent on `paymentId`. |
| `SubySettlement`           | Fans out one pooled USDC / EURC delivery to N merchant wallets via `distribute` (operator only).          |

### `SubySettlement` notes

- `batchId` is single-use: a replay reverts, so re-broadcasting is safe.
- Amounts come from the ledger; the balance is only checked to refuse an underfunded batch (which reverts entirely).
- A failed payout emits `PayoutFailed` without reverting the batch. Retry the unsettled entries under a **new** `batchId`.
- No cap on batch size in the contract: chunking (~29k gas per recipient) is a backend setting.
- Leftovers leave through `rescue` (owner), which stays callable while paused.
- **Risk:** a compromised operator key can send the held balance anywhere. On Base, `owner` and `operator` are the same EOA (`0x8b01…1CB8`), so there is no hot/cold separation.

## Deployments

### `SubyPayment`

| Chain        | Address                                                                                                                         | Tokens          |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| Ethereum     | [`0xb331dc9b1b140c4af40ae8abe4e1d8a1529e5bbe`](https://etherscan.io/address/0xb331dc9b1b140c4af40ae8abe4e1d8a1529e5bbe)          | USDC, USDT, ETH |
| Base         | [`0x8b8f73282c06f1c170101f228618b76eefd02550`](https://basescan.org/address/0x8b8f73282c06f1c170101f228618b76eefd02550)          | USDC, ETH       |
| Arbitrum     | [`0x997cd72dc8b25a5cdc1dbe34fa3fa0f1600124e1`](https://arbiscan.io/address/0x997cd72dc8b25a5cdc1dbe34fa3fa0f1600124e1)           | USDC, ETH       |
| BNB Chain    | [`0x6cf4f2d9a328180fccc312c6c75fe9e0cea4d631`](https://bscscan.com/address/0x6cf4f2d9a328180fccc312c6c75fe9e0cea4d631)           | USDC, USDT, BNB |
| Polygon      | [`0x272a3f2C6e60ca6AB7d543cc2820a7353C167772`](https://polygonscan.com/address/0x272a3f2C6e60ca6AB7d543cc2820a7353C167772)       | USDC, USDT, POL |
| Monad        | [`0x272a3f2C6e60ca6AB7d543cc2820a7353C167772`](https://monadscan.com/address/0x272a3f2C6e60ca6AB7d543cc2820a7353C167772)         | USDC, USDT, MON |
| Arc          | [`0xE1ac50e0CeCe63C24Ab24311Be5a6b8eb67bFC2f`](https://arc.etherscan.io/address/0xE1ac50e0CeCe63C24Ab24311Be5a6b8eb67bFC2f)      | USDC, EURC      |
| Solana       | Anchor program — see documentation                                                                                              | USDC, USDT, SOL |
| Base Sepolia | [`0xA24d25d4FD4402a21dC237E605cd3130d7AF77cd`](https://sepolia.basescan.org/address/0xA24d25d4FD4402a21dC237E605cd3130d7AF77cd) | USDC, ETH       |

### `SubyRelayer`

| Chain   | Address                                                                                                                   | Tokens          |
| ------- | ------------------------------------------------------------------------------------------------------------------------- | --------------- |
| Base    | [`0x1b5cC410042aE2A045ee1b135d46BC7568c0cD61`](https://basescan.org/address/0x1b5cc410042ae2a045ee1b135d46bc7568c0cd61)    | USDC, ETH       |
| Polygon | [`0xE1ac50e0CeCe63C24Ab24311Be5a6b8eb67bFC2f`](https://polygonscan.com/address/0xe1ac50e0cece63c24ab24311be5a6b8eb67bfc2f) | USDC, USDT, POL |

### `SubySettlement`

| Chain | Address                                                                                                                 | Tokens     |
| ----- | ----------------------------------------------------------------------------------------------------------------------- | ---------- |
| Base  | [`0x99c9c5C918fc397Ff20Da5b1686E24ee8249A99E`](https://basescan.org/address/0x99c9c5c918fc397ff20da5b1686e24ee8249a99e) | USDC, EURC |

The earlier build at [`0xcb6c14…139f`](https://basescan.org/address/0xcb6c14af9afec09a3c58c32aeda914f232d1139f) is superseded and holds no funds.

## Usage

```sh
cp .env.example .env
forge install
forge test -vvv
```

Deploy scripts live in `scripts/deploy/`; required env vars are listed at the top of each `.s.sol` file.

```sh
forge script scripts/deploy/SubyMerchantVaultFactory.s.sol:DeploySubyMerchantVaultFactory \
  --rpc-url $RPC_BASE --broadcast --verify
```

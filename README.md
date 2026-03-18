# Gas-Efficient P2P Lending Matching Engine with Aave Integration

A decentralized P2P lending protocol on Ethereum that matches lenders and borrowers on-chain and deposits unmatched lender liquidity into Aave for yield. Built with Foundry and Solidity 0.8.20.

## Features

- **Order-book style queues**: Lenders and borrowers submit orders with amount and rate (bps); matching is rate-then-time priority.
- **Gas-efficient queues**: Bucketed by rate (25 bps steps), bitset for non-empty buckets, linked-list FIFO per bucket (no array shifting).
- **Aave integration**: Unmatched lender funds are supplied to Aave; on match or cancel, only the needed amount is withdrawn.
- **Partial fills**: Orders can be partially filled; remainder stays in queue until filled or cancelled.
- **Repay & withdraw**: Borrowers repay principal (and interest); lenders withdraw via pull pattern.

## Project Structure

```
src/
├── core/
│ ├── P2PLending.sol # Main protocol: orders, matching, repay, withdraw
│ └── AaveConnector.sol # Wraps Aave supply/withdraw; only callable by P2PLending
├── interfaces/
│ ├── IPool.sol # Minimal Aave V3 Pool (supply, withdraw)
│ └── IAToken.sol # Minimal aToken interface
├── libraries/
│ └── OrderTypes.sol # LenderOrder, BorrowOrder, LoanPosition structs; BUCKET_SIZE_BPS
└── mocks/
├── MockERC20.sol # ERC20 with mint (for tests)
└── MockAavePool.sol # Mock Aave pool for tests
test/
└── P2PLending.t.sol # Unit tests (place, match, cancel, repay, withdraw, reverts)
```


## Data Structure Design

### Order types (OrderTypes.sol)

- **LenderOrder**: `owner`, `amount`, `minRateBps`, `createdAt`, `remaining` (packed: uint128/uint32 where possible).
- **BorrowOrder**: `owner`, `amount`, `maxRateBps`, `createdAt`, `remaining`.
- **LoanPosition**: `lender`, `borrower`, `principal`, `rateBps`, `startTime`, `remainingPrincipal`.

Rates are in basis points (bps); 10000 = 100%.

### Queues (gas-efficient)

- **Rate buckets**: Rate is bucketed as `rateBps / 25` (BUCKET_SIZE_BPS). Bucket index capped at 255.
- **Bitset**: One `uint256` per queue (lender/borrow) marks which buckets are non-empty so we never scan empty buckets.
- **FIFO per bucket**: Each bucket is a linked list: `headOrderId`, `tailOrderId`, `orderId → nextOrderId`. Enqueue at tail; dequeue from head; no array shifts.

### Matching logic

- **matchOrders(maxItems)**: At most `maxItems` matches per call (bounded gas).
- **Lender side**: Take the **lowest** non-empty lender bucket (lowest min rate first).
- **Borrower side**: Take the **highest** non-empty borrow bucket (highest max rate first).
- **Match condition**: `lender.minRateBps <= borrower.maxRateBps`. Fill amount = `min(lender.remaining, borrower.remaining)`.
- **After fill**: Update `remaining`; if 0, dequeue. Create `LoanPosition`. Withdraw fill amount from Aave and send to borrower.

## Aave Integration Flow

1. **Lender deposits**: User approves P2PLending → `placeLenderOrder(amount, minRateBps)` → P2PLending pulls tokens → approves AaveConnector → AaveConnector pulls from P2PLending and calls `pool.supply(asset, amount, connector, 0)`. aTokens accrue to the connector.
2. **Match**: When `matchOrders` finds a match, P2PLending calls `connector.withdraw(fillAmount, borrower)` → connector calls `pool.withdraw(asset, amount, borrower)`; borrower receives underlying asset.
3. **Lender cancel**: P2PLending calls `connector.withdraw(order.remaining, lender)`; lender receives principal + any accrued interest (in the mock, 1:1; on real Aave, aToken appreciation).

(Optional: add a sequence diagram here if you use a tool like Mermaid.)

## Gas-Saving Choices

- **Packed structs**: uint128 for amounts, uint32 for rate/timestamp to use storage slots efficiently.
- **Custom errors**: Instead of long `require` strings (e.g. `InvalidAmount()`, `Unauthorized()`).
- **Bounded loops**: `matchOrders(maxItems)` caps work per call.
- **No full-queue iteration**: Bitset + per-bucket linked list; we only walk non-empty buckets and list heads.
- **Single bitset per queue**: 256 buckets in one word; set/clear with bit ops.
- **Pull-based withdraw**: Lenders call `withdraw()` to claim; avoids push and gas spikes.

## Usage

### Build

```bash
forge build
```
### Test

```bash
forge test
```

### Gas report

```bash
forge test --gas-report
```

## Deploy (example with mocks)

Deploy order: MockERC20 → MockAavePool → AaveConnector(pool, asset, P2PLending address) → P2PLending(asset, connector). Use CREATE2 or a factory to get the P2PLending address before deploying the connector, since the connector’s protocol must be the final P2PLending address.

## Security

- ReentrancyGuard on external state-changing functions.
- Pull-based lender withdrawals.
- onlyProtocol on AaveConnector so only P2PLending can deposit/withdraw.

## License

MIT


---

Summary: fix the test by replacing every `.remaining` / `.remainingPrincipal` on mapping getters with destructuring and then asserting on the resulting variables. Use the README as above (and tweak if your repo name or structure differs).
# PLAN.md — CLAWD Stake V2

## Overview

Tiered staking contract for CLAWD token on Base. Users lock a fixed CLAWD amount into one of three tiers for a fixed period, earning 5% yield on locked amount while 5% is burned. Multiple stakes per address allowed, limited slots per tier.

---

## Contracts

### CLAWDStakeV2.sol

Single contract, minimal departure from v1 architecture.

**Storage layout:**
- `Tier` struct: `{ stakeAmount, maxSlots, usedSlots }`
- `StakeInfo` struct: `{ tierIndex, stakeAmount, stakeAt }`
- `mapping(address => StakeInfo[]) public stakes` — array per address
- `mapping(uint256 => Tier) public tiers` — three fixed tiers (0, 1, 2)
- `uint256 public houseReserve` — pre-funded by owner
- `address public owner` — OpenZeppelin Ownable2Step

**Tier config (set at deploy, owner-updatable):**
| Tier | Stake Amount | Max Slots |
|------|-------------|-----------|
| 0 (Small) | 13,030,000 CLAWD | 100 |
| 1 (Medium) | 25,030,000 CLAWD | 20 |
| 2 (Large) | 130,030,000 CLAWD | 10 |

**Key functions:**
- `fundHouseReserve(uint256 amount)` — owner deposits CLAWD for yield + burn
- `stake(uint8 tierIndex)` — user stakes exact tier amount, checks slot availability, records stake
- `unstake(uint8 stakeIndex)` — checks 6-month lock elapsed, sends principal + 5% yield from houseReserve, burns 5% from houseReserve, removes stake
- `setTier(uint8 tierIndex, uint256 stakeAmount, uint256 maxSlots)` — owner updates tier params (must NOT affect existing active stakes)
- `withdrawHouseReserve(uint256 amount)` — owner withdraws excess reserves

**Events:**
- `Stake(address indexed user, uint8 tierIndex, uint256 stakeAt)`
- `Unstake(address indexed user, uint256 stakeIndex, uint256 principal, uint256 yield, uint256 burn)`
- `HouseFunded(uint256 amount)`
- `TierUpdated(uint8 tierIndex, uint256 stakeAmount, uint256 maxSlots)`

**Constants:**
- `LOCK_DURATION = 180 days`
- `YIELD_BPS = 500` (5%)
- `BURN_BPS = 500` (5%)

### Storage.sol

Minimal storage contract if needed for upgrade path. Otherwise, all storage in CLAWDStakeV2.

---

## Security

- CEI (Checks-Effects-Interactions) pattern on all state-changing functions
- ReentrancyGuard on `stake()` and `unstake()`
- SafeERC20 for all token transfers
- Stake index validation on removal (no gap exploitation)
- Tier update: `stakeAmount` and `maxSlots` changes must NOT retroactively affect existing active stakes — only apply to new stakes
- House reserve must hold enough for yield + burn before allowing new stakes (pull pattern)
- OpenZeppelin Ownable2Step for secure ownership transfer

---

## Frontend

- **Stack:** Next.js + wagmi + viem + RainbowKit
- **Chain:** Base (8453)
- **Hosting:** BGIPFS for static frontend; ENS subdomain (stake.clawd.eth or stake.serviceclaw.eth TBD)
- **Wallet:** RainbowKit connect button

**Pages/flows:**
1. **Tier selector** — three tier cards showing amount, slots remaining, lock duration
2. **Active stakes list** — all stakes for connected wallet with time remaining
3. **Unstake button** — enabled after 180 days lock

**States:**
- Connect wallet → Network check (Base) → Tier selection → Approve CLAWD (if needed) → Stake → Confirmation
- Unstake: Connect → Show eligible stakes → Unstake → Confirmation

---

## Testing

- Foundry `forge` tests
- Deploy to Base mainnet (verify with CLAWD token)
- Test: stake, unstake after lock, yield math, burn math, slot limits, tier updates

---

## Deployment

- **Chain:** Base
- **RPC:** Alchemy (mainnet.base.org)
- **Contracts:** Deploy CLAWDStakeV2, configure tiers, fund house reserve
- **Frontend:** IPFS via bgipfs (`NEXT_PUBLIC_IPFS_BUILD=true`)
- **Owner:** Set to `job.client` = `0x34aA3F359A9D614239015126635CE7732c18fDF3`

---

## Repo Structure

```
cv-4/
├── PLAN.md
├── USERJOURNEY.md
├── README.md
├── contracts/
│   ├── CLAWDStakeV2.sol
│   └── .gitkeep
├── test/
│   └── CLAWDStakeV2.t.sol
├── script/
│   └── Deploy.s.sol
└── packages/
    └── nextjs/  (scaffold-eth-2)
```

# CLAWD Stake V2

Tiered staking contract for CLAWD token on Base. Lock CLAWD tokens and earn 5% yield with a 180-day lock.

**Contract:** `0x8410d83faf78313967160b7a45d315cbe66380b2` on Base (chain ID 8453)  
**CLAWD Token:** `0x9F86d2b6FC636C93727614d7e3D959c9dAeDEa67`  
**Owner:** `0x34aA3F359A9D614239015126635CE7732c18fDF3`

## Tiers

| Tier | Stake Amount | Max Slots | Lock |
|------|-------------|-----------|------|
| 🥉 Bronze | 13,030,000 CLAWD | 100 | 180 days |
| 🥈 Silver | 25,030,000 CLAWD | 20 | 180 days |
| 🥇 Gold | 130,030,000 CLAWD | 10 | 180 days |

**Yield:** 5% · **Burn:** 5% of stake amount from house reserve

## Running Locally

```bash
cd packages/nextjs
yarn install
yarn dev
```

## Build for IPFS

```bash
cd packages/nextjs
rm -rf .next out
NEXT_PUBLIC_IPFS_BUILD=true NODE_OPTIONS="--require ./polyfill-localstorage.cjs" npm run build
bgipfs upload out --config ~/.bgipfs/credentials.json
```

## Architecture

- `contracts/CLAWDStakeV2.sol` — single tiered staking contract
- OpenZeppelin: `Ownable2Step`, `ReentrancyGuard`, `SafeERC20`
- CEI pattern on all state-changing functions
- House reserve pre-funded by owner; yield + burn pulled at unstake

## Contracts

| Contract | Address |
|----------|---------|
| CLAWDStakeV2 | `0x8410d83faf78313967160b7a45d315cbe66380b2` |
| CLAWD Token | `0x9F86d2b6FC636C93727614d7e3D959c9dAeDEa67` |

## Security

Audited using ethskills.com audit methodology. 6 checklists applied (general, precision-math, ERC20, staking, access-control, DoS). 37 Foundry tests passing. No critical/high/medium findings.

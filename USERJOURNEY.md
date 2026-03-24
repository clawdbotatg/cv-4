# USERJOURNEY.md — CLAWD Stake V2

## User Flow

### Happy Path: Stake and Earn

1. User lands on app → RainbowKit connect modal appears
2. User clicks "Connect Wallet" → selects MetaMask/wallet
3. App checks: wrong network? → shows "Switch to Base" button → user switches
4. User sees three tier cards:
   - **Tier 0 (Small):** 13,030,000 CLAWD — 100 slots — 180-day lock — 5% yield
   - **Tier 1 (Medium):** 25,030,000 CLAWD — 20 slots — 180-day lock — 5% yield
   - **Tier 2 (Large):** 130,030,000 CLAWD — 10 slots — 180-day lock — 5% yield
5. Each card shows: slots used / max slots, lock period, yield %
6. User clicks "Stake" on desired tier
7. If no prior CLAWD approval: app requests approval for exact tier amount
8. User confirms transaction in wallet
9. Transaction confirmed → stake appears in "My Stakes" list
10. User sees: tier, amount, stake date, unlock date, yield earned (estimated)

### Happy Path: Unstake (After Lock)

1. User connects wallet
2. "My Stakes" shows list of all stakes
3. Stake with lock expired: "Unstake" button is active
4. Stake still locked: "Unstake" button disabled, shows countdown "X days left"
5. User clicks "Unstake" on eligible stake
6. Confirmation modal shows: principal + 5% yield — 5% burn = net return
7. User confirms transaction
8. Transaction confirmed → stake removed from list, CLAWD token returned to wallet

### Edge Cases

#### Wrong Network
- App detects non-Base network → banner: "Please switch to Base"
- "Switch Network" button triggers wallet switch
- If wallet doesn't support chain switching → instructions to manually add Base

#### Insufficient CLAWD Balance
- Stake button disabled
- Shows: "Insufficient CLAWD balance. You have X, need Y."

#### Tier Full (No Slots)
- Stake button disabled on that tier card
- Shows: "All slots full — try another tier or check back later"

#### Wallet Not Connected
- Tier cards visible but "Stake" buttons disabled
- Shows: "Connect wallet to stake"

#### Transaction Rejected
- If user rejects tx → modal closes, no state change
- No error shown (user cancelled)

#### Unstake Before Lock Expires
- "Unstake" button disabled
- Countdown timer shows days/hours remaining
- No way to early unstake (no early withdrawal option per spec)

#### House Reserve Depleted
- If contract doesn't have enough for yield + burn → stake() should revert
- UI shows generic "Transaction failed" — contract enforces pull pattern

#### Zero Stakes
- "My Stakes" empty state: "No active stakes. Select a tier above to start earning."

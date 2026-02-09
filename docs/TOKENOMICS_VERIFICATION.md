**English** | [한국어](TOKENOMICS_VERIFICATION.ko.md)

# Plumise v2 Tokenomics - Mathematical Verification Report

**Verification Date**: 2026-02-10
**Verified By**: Math Analyst (Claude Opus 4.6)
**Subject**: Plumise v2 Genesis System Contracts

---

## 1. Total Supply Verification

### 1.1 Block Reward Sum

Block rewards follow a geometric series:
- Initial reward: 10 PLM/block
- Halving interval: 42,048,000 blocks (approximately 3.997 years at 3 sec/block)
- Halving calculation: `42,048,000 blocks * 3 sec = 126,144,000 sec = 3.997 years`

Infinite sum of the geometric series:

```
S = B * R * sum_{k=0}^{inf} (1/2)^k
  = B * R * 2
  = 42,048,000 * 10 * 2
  = 840,960,000 PLM
```

Verification (partial sum convergence):

| Halving | Block Reward | Period Total | Cumulative Total |
|---------|--------------|--------------|------------------|
| 0 | 10.0 PLM | 420,480,000 | 420,480,000 |
| 1 | 5.0 PLM | 210,240,000 | 630,720,000 |
| 2 | 2.5 PLM | 105,120,000 | 735,840,000 |
| 3 | 1.25 PLM | 52,560,000 | 788,400,000 |
| 4 | 0.625 PLM | 26,280,000 | 814,680,000 |
| ... | ... | ... | -> 840,960,000 |

### 1.2 Total Supply

```
Block Reward Total:   840,960,000 PLM
Genesis Total:        159,040,000 PLM
───────────────────────────────────
Total Supply:       1,000,000,000 PLM (1 billion)
```

**Result: PASS** - Exactly 1 billion PLM

---

## 2. Genesis Distribution Verification

### 2.1 Amount Verification

| Contract | Address | Amount (PLM) | Ratio |
|----------|---------|--------------|-------|
| Foundation Treasury | 0x1001 | 47,712,000 | 30.0000% |
| Ecosystem Fund | 0x1002 | 55,664,000 | 35.0000% |
| Team & Advisors | 0x1003 | 23,856,000 | 15.0000% |
| Liquidity | 0x1004 | 31,808,000 | 20.0000% |
| **Total** | | **159,040,000** | **100.0000%** |

### 2.2 Ratio Accuracy Verification

```
159,040,000 * 30% = 159,040,000 * 30 / 100 = 47,712,000  (exact)
159,040,000 * 35% = 159,040,000 * 35 / 100 = 55,664,000  (exact)
159,040,000 * 15% = 159,040,000 * 15 / 100 = 23,856,000  (exact)
159,040,000 * 20% = 159,040,000 * 20 / 100 = 31,808,000  (exact)
```

All ratios divide evenly into integers with no remainder.

**Result: PASS** - Total 159,040,000 PLM, all ratios exact

---

## 3. FoundationTreasury Vesting

**File**: `/Users/jskim/Desktop/vibe/plumise-contracts/src/FoundationTreasury.sol`

### 3.1 Parameter Verification

| Parameter | Value | Solidity Constant |
|-----------|-------|-------------------|
| totalAllocation | 47,712,000 PLM | `47_712_000 ether` |
| CLIFF_DURATION | 180 days | `180 days` = 15,552,000 seconds |
| VESTING_DURATION | 1080 days | `1080 days` = 93,312,000 seconds |
| Total Duration | 1260 days (42 months) | CLIFF + VESTING |

### 3.2 Formula Verification

Code (`_vestedAmount`, line 76-87):

```solidity
if (timestamp < startTimestamp + CLIFF_DURATION) {
    return 0;                                           // Case A: Cliff period
} else if (timestamp >= startTimestamp + CLIFF_DURATION + VESTING_DURATION) {
    return totalAllocation;                              // Case B: Fully vested
} else {
    uint256 elapsedSinceCliff = timestamp - (startTimestamp + CLIFF_DURATION);
    return (totalAllocation * elapsedSinceCliff) / VESTING_DURATION;  // Case C: Linear vesting
}
```

Mathematical representation:

```
         { 0                                          if t < S + C
v(t) =  { T * (t - S - C) / V                        if S + C <= t < S + C + V
         { T                                          if t >= S + C + V

Where: S = startTimestamp, C = CLIFF_DURATION, V = VESTING_DURATION, T = totalAllocation
```

This is the standard cliff + linear vesting formula and is mathematically correct.

### 3.3 Calculation at Key Time Points

Assuming startTimestamp = 0:

| Time Point | Days Elapsed | elapsedSinceCliff | Vested Amount (PLM) | Ratio |
|------------|--------------|--------------------|--------------------|-------|
| Genesis | Day 0 | cliff | 0 | 0.00% |
| 3 months | Day 90 | cliff | 0 | 0.00% |
| 6 months (cliff end) | Day 180 | 0 seconds | 0 | 0.00% |
| 6 months + 1 day | Day 181 | 86,400 seconds | 44,177.78 | 0.09% |
| 12 months | Day 360 | 180 days | 7,952,000 | 16.67% |
| 18 months | Day 540 | 360 days | 15,904,000 | 33.33% |
| 24 months | Day 720 | 540 days | 23,856,000 | 50.00% |
| 30 months | Day 900 | 720 days | 31,808,000 | 66.67% |
| 36 months | Day 1080 | 900 days | 39,760,000 | 83.33% |
| 42 months (complete) | Day 1260 | - | 47,712,000 | 100.00% |

### 3.4 Precision Analysis

**Overflow check**:
```
totalAllocation * (VESTING_DURATION - 1)
= 47,712,000 * 10^18 * 93,311,999
= 4.45 * 10^33

uint256 max = 1.16 * 10^77

Ratio: 3.84 * 10^-44 (safe)
```

**Rounding error**:
```
Maximum error = VESTING_DURATION - 1 = 93,311,999 wei
= 0.000000000093312 PLM
= 1.96 * 10^-16% of total (negligible)
```

**Monotonicity**:
```
totalAllocation / VESTING_DURATION = 511,316,872,427,983,539 wei/second
>> 1, so at least this amount vests every second (monotonic increase guaranteed)
```

**Completion accuracy**: When `t >= start + CLIFF + VESTING`, `totalAllocation` is returned directly without division, ensuring exact precision.

**Result: PASS** - Formula, precision, and boundary values all correct

---

## 4. TeamVesting Math

**File**: `/Users/jskim/Desktop/vibe/plumise-contracts/src/TeamVesting.sol`

### 4.1 Parameter Verification

| Parameter | Value | Solidity Constant |
|-----------|-------|-------------------|
| totalAllocation | 23,856,000 PLM | `23_856_000 ether` |
| CLIFF_DURATION | 365 days | `365 days` = 31,536,000 seconds |
| VESTING_DURATION | 1095 days | `1095 days` = 94,608,000 seconds |
| Total Duration | 1460 days (48 months, 4 years) | CLIFF + VESTING |

### 4.2 Formula Verification

Code (`_vestedAmount`, line 151-162):

```solidity
function _vestedAmount(uint256 allocation, uint256 timestamp) internal view returns (uint256) {
    if (timestamp < startTimestamp + CLIFF_DURATION) {
        return 0;
    } else if (timestamp >= startTimestamp + CLIFF_DURATION + VESTING_DURATION) {
        return allocation;
    } else {
        uint256 elapsedSinceCliff = timestamp - (startTimestamp + CLIFF_DURATION);
        return (allocation * elapsedSinceCliff) / VESTING_DURATION;
    }
}
```

This has the same mathematical structure as FoundationTreasury, using individual beneficiary `allocation` instead of `totalAllocation`. It is mathematically correct.

### 4.3 Allocation Overflow Protection

```solidity
require(totalAllocated + allocation <= totalAllocation, "Exceeds total allocation");
```

This check ensures that the sum of all beneficiary allocations cannot exceed totalAllocation (23,856,000 PLM). Combined with Solidity 0.8.20's built-in overflow check, this provides dual protection.

### 4.4 Calculation at Key Time Points (Assuming 5,000,000 PLM Allocation)

| Time Point | elapsedSinceCliff | Vested Amount (PLM) | Ratio |
|------------|-------------------|---------------------|-------|
| Day 0 (genesis) | cliff | 0 | 0.00% |
| Day 365 (cliff end) | 0 days | 0 | 0.00% |
| Day 366 (cliff + 1 day) | 1 day | 4,566.21 | 0.09% |
| Day 730 (24 months) | 365 days | 1,666,666.67 | 33.33% |
| Day 1095 (36 months) | 730 days | 3,333,333.33 | 66.67% |
| Day 1460 (48 months, complete) | - | 5,000,000.00 | 100.00% |

### 4.5 Precision Analysis

```
Maximum product: 23,856,000 * 10^18 * 94,607,999 = 2.26 * 10^33 (within uint256 range)
Maximum rounding error: 94,607,999 wei = 0.000000000094608 PLM (negligible)
```

### 4.6 removeBeneficiary Accounting Accuracy

```solidity
totalAllocated -= b.allocation;  // Subtract the full original allocation
```

Already released tokens have been transferred, and the full original allocation is subtracted from `totalAllocated`, making the accounting correct.

**Result: PASS** - Formula, overflow protection, and accounting logic all correct

---

## 5. EcosystemFund Rate Limit

**File**: `/Users/jskim/Desktop/vibe/plumise-contracts/src/EcosystemFund.sol`

### 5.1 Rate Limit Calculation

```solidity
uint256 maxAmount = (totalAllocation * RATE_LIMIT_PERCENT) / 100;
// = (55,664,000 * 10^18 * 5) / 100
// = 278,320,000 * 10^18 / 100
// = 2,783,200 * 10^18
// = 2,783,200 PLM
```

### 5.2 Precision Verification

```
55,664,000 * 10^18 * 5 = 278,320,000,000,000,000,000,000,000
278,320,000,000,000,000,000,000,000 % 100 = 0

Precision loss: ZERO (perfect integer division)
```

### 5.3 Timelock Verification

```
TIMELOCK_DURATION = 24 hours = 86,400 seconds (using Solidity 'hours' keyword)
```

### 5.4 Maximum Withdrawal Rate Analysis

```
Maximum per transaction: 2,783,200 PLM (5% of total)
Minimum interval: 24 hours
Time to fully withdraw: 55,664,000 / 2,783,200 = 20 days
```

### 5.5 Design Characteristics

- Rate limit is based on **totalAllocation** (initial amount), not current balance
- Rate limit remains unchanged as balance decreases (fixed at 2,783,200 PLM)
- `transferBatch()` applies the same rate limit to the total sum
- When emergency mode is activated, both rate limit and timelock are bypassed

**Result: PASS** - Rate limit calculation exact, no precision loss

---

## 6. RewardPool Epoch Math

**File**: `/Users/jskim/Desktop/vibe/plumise-contracts/src/RewardPool.sol`

### 6.1 Epoch Calculation

```solidity
uint256 public constant BLOCKS_PER_EPOCH = 1200;

function getCurrentEpoch() public view returns (uint256) {
    return (block.number - deployBlock) / BLOCKS_PER_EPOCH;
}
```

```
1200 blocks * 3 sec/block = 3,600 sec = 1 hour/epoch
```

| block.number | epoch | Block within epoch |
|-------------|-------|--------------------|
| 0 | 0 | 0 |
| 1199 | 0 | 1199 |
| 1200 | 1 | 0 |
| 2400 | 2 | 0 |
| 12000 | 10 | 0 |

### 6.2 Score Calculation

```solidity
function calculateScore(Contribution memory contribution) internal view returns (uint256) {
    return
        contribution.taskCount * taskWeight +
        contribution.uptimeSeconds * uptimeWeight +
        contribution.responseScore * responseWeight;
}
```

Default weights: `taskWeight=50, uptimeWeight=30, responseWeight=20` (sum = 100)

Mathematical representation: `score = T*w_t + U*w_u + R*w_r` (weighted sum)

### 6.3 Reward Distribution Formula

```solidity
uint256 reward = (totalReward * score) / totalScore;
```

This is the standard pro-rata distribution formula:

```
reward_i = floor(totalReward * score_i / totalScore)
```

### 6.4 Overflow Analysis

```
Maximum epoch reward: 10 PLM * 1200 blocks = 12,000 PLM = 12,000 * 10^18 wei
Practical maximum score: ~160,000 (taskCount=1000, uptime=3600, response=100)

Maximum product: 12,000 * 10^18 * 160,000 = 1.92 * 10^27
uint256 max: 1.16 * 10^77

Overflow: impossible (safe)
```

### 6.5 Rounding Dust Analysis

```
Floor division in pro-rata distribution may generate dust
Maximum dust = (agentCount - 1) wei per distribution
Dust remains in the RewardPool contract (not lost)
```

### 6.6 syncRewards Mechanism

When Geth's `Finalize()` adds rewards via `state.AddBalance()`, `receive()` is not invoked. `syncRewards()` detects untracked rewards by computing `balance - lastTrackedBalance`.

```
receive(): epochRewards[epoch] += msg.value; lastTrackedBalance = balance;
syncRewards(): newRewards = balance - lastTrackedBalance; epochRewards[epoch] += newRewards;
claimReward(): lastTrackedBalance = balance; (updated after withdrawal)
```

Double-counting prevention is correctly implemented.

### 6.7 Caveats

- **Score overflow**: If the oracle reports extremely large values (e.g., `taskCount = 2^200`), `taskCount * taskWeight` may overflow. However, Solidity 0.8.20's built-in overflow check will revert the transaction, so there is no risk of fund loss. Since only authorized addresses can call the oracle, the practical risk is low.

**Result: PASS** - Epoch calculation, pro-rata distribution, and sync mechanism all correct

---

## 7. Wei Conversion Verification

### 7.1 Per-Address Verification

| Address | PLM | Calculation (PLM * 10^18) | Genesis Value | Match |
|---------|-----|---------------------------|---------------|-------|
| 0x1001 | 47,712,000 | 47712000000000000000000000 | 47712000000000000000000000 | PASS |
| 0x1002 | 55,664,000 | 55664000000000000000000000 | 55664000000000000000000000 | PASS |
| 0x1003 | 23,856,000 | 23856000000000000000000000 | 23856000000000000000000000 | PASS |
| 0x1004 | 31,808,000 | 31808000000000000000000000 | 31808000000000000000000000 | PASS |

### 7.2 Digit Count Verification

All values are 26 digits (8-digit PLM + 18 digits for 10^18 decimal):
```
47,712,000 = 8 digits
10^18 = 18 zeros
Total: 26 digits (no leading zeros)
```

### 7.3 Solidity `ether` Keyword Verification

In the contracts, `47_712_000 ether` is equivalent to `47_712_000 * 10^18` in Solidity. This matches the balance values in the Genesis JSON.

**Result: PASS** - All Wei conversions exact

---

## 8. Additional Security Analysis

### 8.1 Reentrancy Protection

All contracts use OpenZeppelin `ReentrancyGuard` and perform state changes before external calls (`call{value:}`) following the CEI (Checks-Effects-Interactions) pattern:

- **FoundationTreasury**: `released += releasable` before `call{value:}` (line 48-49)
- **TeamVesting**: `beneficiaries[beneficiary].released += releasable` before `call{value:}` (line 110-112)
- **RewardPool**: `pendingRewards[msg.sender] = 0` before `call{value:}` (line 200-203) -- CEI pattern + nonReentrant
- **EcosystemFund**: `lastTransferTimestamp = block.timestamp` before `call{value:}` (line 62-64)

### 8.2 Access Control

| Contract | Key Function | Restriction |
|----------|-------------|-------------|
| FoundationTreasury | release() | onlyOwner |
| EcosystemFund | transfer(), transferBatch() | onlyOwner |
| TeamVesting | addBeneficiary(), removeBeneficiary() | onlyOwner |
| TeamVesting | release() | Callable by anyone (safe: tokens are sent to the beneficiary) |
| LiquidityDeployer | transfer() | onlyOwner |
| RewardPool | reportContribution() | oracle only |
| RewardPool | setOracle(), setRewardFormula() | onlyOwner |
| RewardPool | claimReward() | Registered agents only |

### 8.3 Solidity Version

All contracts use `pragma solidity 0.8.20` with built-in overflow/underflow checks enabled.

---

## Final Verdict

| Verification Item | Result |
|-------------------|--------|
| 1. Total Supply (1 billion PLM) | **PASS** |
| 2. Genesis Distribution (159,040,000 PLM, ratios exact) | **PASS** |
| 3. FoundationTreasury Vesting (6m cliff + 36m linear) | **PASS** |
| 4. TeamVesting Math (12m cliff + 36m linear) | **PASS** |
| 5. EcosystemFund Rate Limit (5%, 24h timelock) | **PASS** |
| 6. RewardPool Epoch Math (1200 blocks/epoch, pro-rata distribution) | **PASS** |
| 7. Wei Conversion (all genesis values) | **PASS** |

### Overall Result: ALL PASS

### Issues Found: None (Critical/High/Medium)

### Notes (Low/Informational):

1. **EcosystemFund Rate Limit Basis**: The rate limit is based on totalAllocation (initial value), so it remains at 2,783,200 PLM even when the balance is very low. When balance < rate limit, the `address(this).balance >= amount` check naturally constrains withdrawals.

2. **RewardPool Score Overflow**: If the oracle reports extreme values, Solidity 0.8.20's overflow check will revert the transaction. There is no risk of fund loss, but proper range validation in the oracle implementation is recommended.

3. **Rounding Dust**: All pro-rata distributions may leave negligible dust in the contract due to floor division. This is intended behavior, and the amounts are negligible at the wei level.

4. **Halving Precision**: 42,048,000 blocks * 3 seconds = 3.997 years (based on 365.25 days/year). This is not exactly 4 years, but this is a standard characteristic of block-based halving (Bitcoin exhibits the same behavior).

---

*Verification complete. All mathematical calculations are correct and suitable for Genesis embedding.*

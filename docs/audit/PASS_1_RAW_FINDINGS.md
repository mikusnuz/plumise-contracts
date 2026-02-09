# Security Audit - Pass 1 Raw Findings (Pre-Remediation)
## Plumise v2 Genesis System Contracts

**Auditor**: Genesis System Contracts Security Team
**Date**: 2026-02-10
**Scope**: RewardPool, FoundationTreasury, EcosystemFund, TeamVesting, LiquidityDeployer

---

## Executive Summary

This audit examines 5 system contracts intended for genesis deployment on Plumise v2 chain. Since these contracts are **immutable after genesis**, a comprehensive security review is critical.

### Summary
- **Critical**: 2
- **High**: 4
- **Medium**: 5
- **Low**: 3
- **Informational**: 4

### Total Findings: 18

---

## Critical Findings

### [CRITICAL-01] RewardPool: Missing Balance Check Allows Underflow in syncRewards
- **Severity**: Critical
- **File**: RewardPool.sol:89-100
- **Description**: `syncRewards()` function requires `currentBalance > lastTrackedBalance` but this can fail if rewards are distributed between blocks. When `claimReward()` is called, it reduces the contract balance, but `lastTrackedBalance` is updated. If another `syncRewards()` call happens before new rewards arrive, the function will revert.
- **Impact**:
  - DOS attack vector: Anyone can call `syncRewards()` immediately after a claim, causing revert
  - Block rewards cannot be tracked if claims happen between reward deposits
  - Geth integration broken if rewards arrive continuously but claims happen in between
- **Recommendation**:
```solidity
function syncRewards() external {
    uint256 currentBalance = address(this).balance;
    if (currentBalance <= lastTrackedBalance) {
        return; // No new rewards, exit gracefully
    }

    uint256 newRewards = currentBalance - lastTrackedBalance;
    uint256 epoch = getCurrentEpoch();

    epochRewards[epoch] += newRewards;
    lastTrackedBalance = currentBalance;

    emit RewardReceived(newRewards, epoch);
}
```

### [CRITICAL-02] RewardPool: Unbounded Array Iteration in distributeRewards
- **Severity**: Critical
- **File**: RewardPool.sol:145-189
- **Description**: `distributeRewards()` iterates over `epochAgents[epoch]` array twice (lines 163-167, 177-185) without any limit. If hundreds or thousands of agents contribute in a single epoch, the function will exceed block gas limit and permanently fail.
- **Impact**:
  - Rewards for that epoch become permanently locked
  - No way to distribute rewards if agent count is too high
  - Attackers can register many agents and report minimal contributions to DOS the system
- **Recommendation**:
  - Implement pagination: `distributeRewards(uint256 epoch, uint256 startIndex, uint256 count)`
  - Or use pull-over-push pattern where each agent claims their own share
  - Add maximum agent limit per epoch (e.g., 100 agents)

---

## High Severity Findings

### [HIGH-01] EcosystemFund: Emergency Mode Bypass Allows Complete Drain
- **Severity**: High
- **File**: EcosystemFund.sol:119-124
- **Description**: Owner can enable `emergencyMode` to bypass all rate limits and timelocks, allowing instant withdrawal of entire fund (55.664M PLM). If owner key is compromised, attacker can drain everything in one transaction.
- **Impact**: Complete loss of ecosystem funds (55.664M PLM ≈ significant value)
- **Recommendation**:
  - Remove emergency mode entirely, or
  - Require multi-sig approval for emergency mode activation, or
  - Add separate emergency withdrawal limit (e.g., max 10% even in emergency)
  - Add timelock to emergency mode activation itself (24h delay)

### [HIGH-02] TeamVesting: removeBeneficiary Array Manipulation is Expensive and Error-Prone
- **Severity**: High
- **File**: TeamVesting.sol:78-98
- **Description**: `removeBeneficiary()` uses linear search (O(n)) to find and remove beneficiary from array. If there are 100+ beneficiaries, this becomes very expensive. Additionally, the swap-and-pop pattern changes array order, which may break off-chain indexers.
- **Impact**:
  - High gas costs for removing beneficiaries
  - Potential out-of-gas if beneficiary list is large
  - Array order changes break external systems tracking beneficiaries
- **Recommendation**:
  - Use mapping(address => uint256) to store array index
  - Update index mapping when swapping elements
  - Consider if removal is necessary post-genesis, or only allow adding

### [HIGH-03] FoundationTreasury & TeamVesting: Integer Division Precision Loss in Vesting
- **Severity**: High
- **File**: FoundationTreasury.sol:86, TeamVesting.sol:161
- **Description**: Linear vesting calculation uses integer division which can cause precision loss:
```solidity
return (totalAllocation * elapsedSinceCliff) / VESTING_DURATION;
```
If `totalAllocation = 23,856,000 ether` and elapsed time is small (e.g., 1 day), the calculation loses precision. Accumulated over time, this can result in beneficiaries not receiving full allocation.
- **Impact**:
  - Beneficiaries may not be able to withdraw full allocation even after vesting completes
  - Dust amounts trapped in contract permanently
  - Example: 23,856,000 ether / 1095 days = ~21.78 PLM per day, but integer division may round down
- **Recommendation**:
  - Use higher precision: multiply by 1e18 first, then divide
  - Or check at end: if `timestamp >= end && released < allocation`, allow full withdrawal
  - Better: `return allocation - ((allocation * (vestingEnd - timestamp)) / VESTING_DURATION)`

### [HIGH-04] RewardPool: Reentrancy in claimReward Despite Guard
- **Severity**: High (Low if receivers are trusted)
- **File**: RewardPool.sol:194-208
- **Description**: Although `nonReentrant` modifier is used, the `call{value}` allows the receiver to execute arbitrary code. If the receiver is a contract (agent), it can make external calls during the callback. Combined with the fact that `lastTrackedBalance` is updated AFTER the transfer (line 206), there is a potential for state inconsistency.
- **Impact**:
  - If receiver contract interacts with other parts of the system during callback, state may be inconsistent
  - Edge case: if receiver calls `syncRewards()` during callback, balance tracking may break
- **Recommendation**:
  - Move `lastTrackedBalance` update BEFORE the transfer:
```solidity
pendingRewards[msg.sender] = 0;
lastTrackedBalance = address(this).balance - reward; // Update before transfer

(bool success, ) = msg.sender.call{value: reward}("");
require(success, "Transfer failed");
```

---

## Medium Severity Findings

### [MEDIUM-01] EcosystemFund: transferBatch Can Partially Fail Leaving Inconsistent State
- **Severity**: Medium
- **File**: EcosystemFund.sol:75-115
- **Description**: `transferBatch()` transfers to multiple recipients in a loop (lines 104-112). If any transfer fails, the entire transaction reverts. However, `lastTransferTimestamp` is updated BEFORE the loop (line 102), so if a transfer in the middle fails, the timelock is still consumed but no funds are transferred.
- **Impact**:
  - Timelock consumed with no successful transfers
  - Need to wait another 24 hours to retry
  - Griefing attack: send batch with one invalid recipient to DOS the fund
- **Recommendation**:
  - Move `lastTransferTimestamp` update to AFTER successful loop completion
  - Or validate all recipients before updating timestamp

### [MEDIUM-02] RewardPool: Missing Access Control on distributeRewards
- **Severity**: Medium
- **File**: RewardPool.sol:145
- **Description**: `distributeRewards(uint256 epoch)` is external and can be called by anyone. While this is somewhat intended (permissionless distribution), it opens griefing vectors:
  - Attacker can call it immediately when epoch ends, even if no contributions yet
  - If calling costs high gas but no rewards, attacker wastes caller's gas
  - No incentive mechanism for callers
- **Impact**:
  - Front-running: malicious actor can distribute before legitimate caller
  - No reward for caller who pays gas to distribute to all agents
- **Recommendation**:
  - Add small reward (e.g., 0.1% of epoch rewards) to `msg.sender` who calls distribute
  - Or restrict to oracle/owner for first 24 hours after epoch ends, then open to public

### [MEDIUM-03] All Contracts: Missing Contract Pause Mechanism
- **Severity**: Medium
- **File**: All contracts
- **Description**: None of the contracts have an emergency pause mechanism. If a critical bug is discovered post-genesis, there is no way to stop operations except transferring ownership to a burn address.
- **Impact**:
  - Cannot stop ongoing attacks or exploits
  - Cannot freeze contracts while investigating issues
  - Only option is permanent shutdown (ownership transfer to 0x0)
- **Recommendation**:
  - Add OpenZeppelin `Pausable` to all contracts
  - Add `whenNotPaused` modifier to state-changing functions
  - Owner can pause/unpause

### [MEDIUM-04] LiquidityDeployer: wrapAndAddLiquidity is Incomplete Placeholder
- **Severity**: Medium
- **File**: LiquidityDeployer.sol:48-67
- **Description**: The function only emits an event but doesn't actually wrap PLM or add liquidity (lines 60-66 comment says "simplified version"). This is a critical function for deploying 31.808M PLM to DEX.
- **Impact**:
  - Function is non-functional, requiring a contract upgrade (impossible after genesis)
  - Owner must manually wrap PLM and add liquidity, more error-prone
  - If relied upon, funds will be stuck
- **Recommendation**:
  - Either implement full functionality with WPLM wrapping + Router approval + addLiquidity call
  - Or remove this function and only keep `transfer()`, document that liquidity must be added manually

### [MEDIUM-05] RewardPool: Oracle Centralization Risk
- **Severity**: Medium
- **File**: RewardPool.sol:22, 109-139
- **Description**: Only a single `oracle` address can report contributions. This is a single point of failure. If oracle key is lost or compromised:
  - Lost: no contributions can be reported, agents cannot earn rewards
  - Compromised: attacker can report fake contributions to siphon rewards
- **Impact**:
  - Total system failure if oracle is unavailable
  - Fraudulent reward distribution if oracle is compromised
- **Recommendation**:
  - Use multi-oracle system with quorum (e.g., 3 oracles, 2-of-3 consensus)
  - Or use decentralized oracle network like Chainlink
  - Add oracle rotation mechanism

---

## Low Severity Findings

### [LOW-01] RewardPool: getCurrentEpoch Can Underflow Before deployBlock
- **Severity**: Low
- **File**: RewardPool.sol:265-267
- **Description**: If `block.number < deployBlock` (should never happen, but for completeness), subtraction will underflow. Solidity 0.8.20 will revert, but this is unexpected behavior.
- **Impact**: Unlikely to occur, but if genesis is mishandled, contract may be unusable
- **Recommendation**: Add check:
```solidity
function getCurrentEpoch() public view returns (uint256) {
    if (block.number < deployBlock) return 0;
    return (block.number - deployBlock) / BLOCKS_PER_EPOCH;
}
```

### [LOW-02] TeamVesting & FoundationTreasury: No Event Emitted on receive()
- **Severity**: Low
- **File**: TeamVesting.sol:196-198, FoundationTreasury.sol:93-95
- **Description**: Both contracts emit `Received` event in `receive()`, but these events will be fired during genesis allocation. This is noisy and not useful since genesis is a special case, not a normal transfer.
- **Impact**:
  - Event logs polluted with genesis allocation events
  - Off-chain indexers may misinterpret these as normal deposits
- **Recommendation**:
  - Remove events from `receive()` or
  - Add flag to distinguish genesis vs. normal deposits

### [LOW-03] EcosystemFund: getTimeUntilUnlock Returns 0 for Both "Ready" and "Emergency"
- **Severity**: Low
- **File**: EcosystemFund.sol:138-149
- **Description**: Function returns 0 both when emergency mode is enabled and when timelock has expired. Caller cannot distinguish between these two states.
- **Impact**:
  - UI/frontend cannot show accurate status ("Emergency mode" vs "Ready to transfer")
- **Recommendation**:
  - Return different sentinel values (e.g., `type(uint256).max` for emergency mode)
  - Or add separate `isUnlocked()` and `isEmergencyMode()` view functions

---

## Informational Findings

### [INFO-01] All Contracts: No Constructor Argument Validation for Zero Address
- **Severity**: Informational
- **File**: All contracts
- **Description**: While RewardPool validates constructor args, others don't. For genesis deployment, this doesn't matter (storage slots are set directly), but for testing/non-genesis deploys, passing wrong args can brick the contract.
- **Recommendation**: Add validation in all constructors for completeness

### [INFO-02] RewardPool: Contribution.totalTokens Field is Unused
- **Severity**: Informational
- **File**: IRewardPool.sol:19, RewardPool.sol:274-278
- **Description**: The struct field `totalTokens` is never set or used. This is dead code.
- **Recommendation**: Remove field or implement token tracking logic

### [INFO-03] Missing NatSpec Documentation for Internal Functions
- **Severity**: Informational
- **File**: RewardPool.sol:274, FoundationTreasury.sol:76, TeamVesting.sol:151
- **Description**: Internal functions `calculateScore()`, `_vestedAmount()` lack NatSpec comments.
- **Recommendation**: Add documentation for maintainability

### [INFO-04] Gas Optimization: Cache Array Length in Loops
- **Severity**: Informational
- **File**: RewardPool.sol:163, 177, EcosystemFund.sol:83, 104
- **Description**: Using `agents.length` or `amounts.length` in loop condition reads from storage/memory repeatedly.
- **Recommendation**: Cache length:
```solidity
uint256 len = agents.length;
for (uint256 i = 0; i < len; i++) { ... }
```

---

## Genesis Compatibility Review

### Immutable Variables: ✅ PASS
- No `immutable` keywords used in any contract
- All constructor-set values use regular storage variables

### Constructor Behavior: ✅ PASS
- All constructors only set storage variables
- No external calls or complex logic
- Storage slots can be overridden in genesis

### Receive Function: ✅ PASS
- All `receive()` functions are simple and safe
- Genesis allocation will call these successfully

---

## Recommendations Priority

1. **MUST FIX** (Critical/High):
   - CRITICAL-01: Fix syncRewards underflow
   - CRITICAL-02: Add pagination to distributeRewards
   - HIGH-01: Remove or restrict emergency mode
   - HIGH-03: Fix vesting precision loss
   - MEDIUM-04: Implement or remove wrapAndAddLiquidity

2. **SHOULD FIX** (Medium):
   - MEDIUM-01: Fix transferBatch timelock logic
   - MEDIUM-02: Add incentive to distributeRewards caller
   - MEDIUM-03: Add pause mechanism

3. **NICE TO HAVE** (Low/Info):
   - LOW-01: Add getCurrentEpoch underflow check
   - INFO-02: Remove unused totalTokens field

---

## Conclusion

The contracts have **2 critical** and **4 high** severity issues that **must be resolved** before genesis deployment. The most critical issues are:

1. RewardPool's unbounded loop in distributeRewards (gas DOS)
2. RewardPool's syncRewards underflow (functional break)
3. Vesting precision loss (fund leakage)
4. Emergency mode bypass (security risk)

**Overall Assessment**: ❌ **NOT READY FOR GENESIS DEPLOYMENT**

Recommended Actions:
1. Fix all Critical and High issues
2. Review and test all Medium issues
3. Deploy to testnet and run comprehensive tests
4. Conduct second audit after fixes

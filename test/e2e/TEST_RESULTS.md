# Plumise v2 Testnet E2E Test Results

**Date**: 2026-02-11
**Chain ID**: 419561
**RPC**: https://plug.plumise.com/rpc/testnet
**Block Range**: 11991 - 12007

## Summary

| Test | Result | Notes |
|------|--------|-------|
| Test 1: Agent Registration | ✅ PASS | Successfully registered agent via precompile 0x21 |
| Test 2: Agent Heartbeat | ✅ PASS | Heartbeat signal sent, lastHeartbeat updated |
| Test 3: Verify Inference | ❌ FAIL | **SECURITY ISSUE**: Non-agent can call verifyInference |
| Test 4: Claim Reward | ✅ PASS | Claim process works (no rewards yet) |
| Test 5: Edge Cases | ✅ PASS | Most edge cases handled correctly |

**Overall**: 4/5 tests passed

## Detailed Results

### Test 1: Agent Registration ✅

**Agent Address**: `0xf9d08344BA72513760563Ae1AE7491b54706DB1a`

- ✅ Agent funded with 10 PLM
- ✅ Registration transaction successful (block 11991)
- ✅ Agent state created in blockchain
- ⚠️ RPC methods `agent_isAgentAccount` and `agent_getAgentMeta` have parameter issues but `agent_getStatus` works

**Transaction**: `0x39872e2bc9be5e9fcf6ece4d7c3a5fc82899f65b5676d6ca4275cc043ce4e3d7`

**Agent State** (from `agent_getStatus`):
```json
{
  "address": "0xf9d08344ba72513760563ae1ae7491b54706db1a",
  "registered": true,
  "active": true,
  "nodeId": "",
  "lastHeartbeat": "0x0",
  "registeredAt": "0x698c3793",
  "totalRewards": "0x0",
  "metadata": "e2e-test-agent"
}
```

### Test 2: Agent Heartbeat ✅

- ✅ Heartbeat transaction successful (block 11993)
- ✅ `lastHeartbeat` updated from `0x0` to `0x698c3799` (timestamp: 1769576345 = 2026-01-27 19:59:05 UTC)
- ✅ Agent status remains `active`

**Transaction**: `0xbb4d712cf71caec04c1c1c34970a8bb57cbe39cdc2ab916a35b7b37205806339`

**Updated State**:
```json
{
  "address": "0xf9d08344ba72513760563ae1ae7491b54706db1a",
  "registered": true,
  "active": true,
  "lastHeartbeat": "0x698c3799",
  "registeredAt": "0x698c3793"
}
```

### Test 3: Verify Inference ❌ SECURITY ISSUE

- ✅ verifyInference called from agent address - transaction successful (block 11995)
- ❌ **CRITICAL**: verifyInference called from non-agent address **also succeeded** (block 11997)

**Agent Transaction**: `0x08d77e3b34c9a03dd7ecdccb0d29203059e1af47ab3be40f9f444e5cf4fd076f`
**Non-Agent Transaction**: `0x0524731629ff018343c951a93ade9a9ff20dd3fba5d3844ed76c5b953bb8b46f`

#### Security Issue Details

The precompile at `0x20` (`verifyInference`) should validate that `msg.sender` is a registered agent. Currently, **any address can call this precompile**, which means:

1. Non-agents can forge inference records
2. Rewards could be claimed fraudulently
3. Agent reputation metrics are unreliable

**Recommendation**: Add caller validation in the precompile:
```go
// In precompile 0x20
caller := evm.StateDB.GetAgentAccount(msg.sender)
if caller == nil || !caller.Registered {
    return nil, ErrNotRegisteredAgent
}
```

### Test 4: Claim Reward ✅

- ✅ RewardPool has sufficient balance (119,970 PLM)
- ✅ Claim transaction successful (block 11998)
- ✅ No rewards claimed (expected, as no contributions were reported)

**Transaction**: `0x9d0cdb84b97eeb38ba531b269b1a434d4dd9b4986b61699f7abe5270b91ad5c4`

**Balance**:
- Before: 9.99969014845 PLM
- After: 9.99966452095 PLM
- Difference: -0.0000256275 PLM (gas cost only, no reward)

### Test 5: Edge Cases ✅

#### 5.1: Double Registration
- ✅ Attempting to register the same address twice **failed** as expected
- Transaction reverted correctly

**Transaction**: `0xbed37acea8178657414decc981ab7a498cb649776cf3a806599f589ceae51faa`

#### 5.2: Heartbeat from Non-Agent
- ✅ Non-registered address sending heartbeat **failed** as expected
- Transaction reverted correctly

**Transaction**: `0x10eff870fddec1fea27ce82a50be5eb57984762ba2235ea61c122a7de9afe4ed`

#### 5.3: verifyInference from Wrong Caller
- ❌ Already covered in Test 3 - **security issue identified**

#### 5.4: Registration with Empty Name
- ⚠️ Registration with empty name **succeeded** (block 12007)
- This may be intentional (anonymous agents allowed)

**Transaction**: `0xd4e5c68c3fecb0b1e308cc3fb3fed4c6a00856a4e36c08cae2d149f71a806e65`

## RPC Method Issues

The following RPC methods have parameter format issues:

- `agent_isAgentAccount(address)` - Returns error: "missing value for required argument 1"
- `agent_getAgentMeta(address)` - Returns error: "missing value for required argument 1"

However, `agent_getStatus(address)` works correctly.

**Recommendation**: Check the RPC API implementation to ensure parameter parsing is consistent across all agent-related methods.

## Recommendations

### Critical (Security)

1. **Fix verifyInference caller validation** - Precompile 0x20 must validate that `msg.sender` is a registered agent
2. **Add integration tests in geth** - Unit tests for precompiles with caller validation

### High (Functionality)

3. **Fix RPC methods** - `agent_isAgentAccount` and `agent_getAgentMeta` parameter parsing
4. **Add status field** - The `agent_getStatus` response is missing the `status` field (only shows `active` boolean)

### Medium (Enhancement)

5. **Consider name validation** - Decide if empty names should be allowed for agents
6. **Add TotalInferences tracking** - Metadata should include inference count for monitoring

## Conclusion

The Plumise v2 testnet agent system is **mostly functional** but has **one critical security issue**:

- ✅ Agent registration works
- ✅ Heartbeat mechanism works
- ✅ Reward claiming process works
- ❌ **Inference verification lacks caller validation**
- ✅ Most edge cases are handled correctly

**Action Required**: Fix the `verifyInference` precompile caller validation before mainnet deployment.

---

**Test Script**: `/Users/jskim/Desktop/vibe/plumise-contracts/test/e2e/testnet-e2e.ts`
**Run**: `cd test/e2e && npm test`

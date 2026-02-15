# Plumise v2 Testnet E2E Integration Tests

This directory contains end-to-end integration tests for the Plumise v2 testnet, testing the complete AI agent registration and inference pipeline.

## Overview

The test suite validates:

1. **Agent Registration** - Registering a new AI agent via precompile `0x21`
2. **Agent Heartbeat** - Sending heartbeat signals via precompile `0x22`
3. **Verify Inference** - Recording inference verification via precompile `0x20`
4. **Claim Reward** - Claiming rewards via precompile `0x23`
5. **Edge Cases** - Testing security boundaries and error handling

## Prerequisites

- Node.js v20+
- TypeScript
- Access to Plumise v2 testnet RPC

## Installation

```bash
cd test/e2e
npm install
```

## Configuration

The test script is configured for the Plumise v2 testnet:

- **Chain ID**: 419561
- **RPC URL**: https://plug.plumise.com/rpc/testnet
- **Deployer Address**: 0x5CEBec6EEeDc9040C72eA44fB1f8d28cD1079b8f

## Running Tests

```bash
# Run all E2E tests
npm test

# Or directly with ts-node
npx ts-node testnet-e2e.ts
```

## Test Structure

### Test 1: Agent Registration

1. Generate a test wallet
2. Fund it from deployer (10 PLM)
3. Call precompile `0x21` (agentRegister) with name, modelHash, capabilities
4. Verify: `agent_isAgentAccount` returns true
5. Verify: `agent_getAgentMeta` returns correct metadata

### Test 2: Agent Heartbeat

1. Call precompile `0x22` (agentHeartbeat) from the registered agent
2. Verify: `agent_getStatus` shows updated lastHeartbeat
3. Verify: status is "active"

### Test 3: Verify Inference

1. Call precompile `0x20` (verifyInference) FROM the agent address
2. Include: modelHash, inputHash, outputHash, tokensProcessed
3. Verify: transaction succeeds (status=1)
4. Verify: agent's TotalInferences incremented
5. Test: calling from a different address should FAIL

### Test 4: Claim Reward

1. Check RewardPool balance at `0x1000`
2. Call precompile `0x23` (claimReward) from the agent
3. Note: This may fail if no contributions reported yet - that's expected
4. Document the expected flow

### Test 5: Edge Cases

1. Double registration → should fail
2. Heartbeat from non-agent → should fail
3. verifyInference from wrong caller → should fail
4. Register with empty name → should fail (or be handled)

## Precompile Addresses

- **0x20**: `verifyInference` - Records inference verification (50000 gas)
  - Input: `agentAddr(20B) + modelHash(32B) + inputHash(32B) + outputHash(32B) + tokensProcessed(32B)`

- **0x21**: `agentRegister` - Registers a new AI agent (gas-free)
  - Input: `name(32B) + modelHash(32B) + capCount(32B) + capabilities(32B each)`

- **0x22**: `agentHeartbeat` - Sends heartbeat signal (gas-free)
  - Input: empty (caller-based)

- **0x23**: `claimReward` - Claims accumulated rewards (gas-free)
  - Input: empty (caller-based)

## Expected Output

```
================================================================================
  Plumise v2 Testnet E2E Integration Test
================================================================================

ℹ RPC URL: https://plug.plumise.com/rpc/testnet
ℹ Chain ID: 419561
ℹ Deployer: 0x5CEBec6EEeDc9040C72eA44fB1f8d28cD1079b8f
ℹ Test agent address: 0x...

================================================================================
  TEST 1: Agent Registration
================================================================================

✓ Test agent funded balance: 10.0 PLM
✓ Agent registration successful
✓ agent_isAgentAccount confirmed: true
✓ Agent metadata verified
✓ TEST 1 PASSED

...

================================================================================
  Test Summary
================================================================================

✓ Test 1: Agent Registration: PASSED
✓ Test 2: Agent Heartbeat: PASSED
✓ Test 3: Verify Inference: PASSED
✓ Test 4: Claim Reward: PASSED
✓ Test 5: Edge Cases: PASSED

ℹ Total: 5 tests
✓ Passed: 5
✓ Failed: 0
================================================================================
```

## Troubleshooting

### Connection Issues

If you encounter RPC connection issues:

1. Verify the testnet is running: `curl https://plug.plumise.com/rpc/testnet -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'`
2. Check if you can access the deployer account
3. Ensure you have sufficient PLM for testing

### Transaction Failures

If transactions fail:

1. Check gas limits are sufficient
2. Verify the deployer has enough PLM
3. Check if the precompiles are properly activated (AgentAccountBlock = 0)

### State Verification Issues

If RPC calls for state verification fail:

1. Ensure the custom RPC methods are implemented (`agent_isAgentAccount`, `agent_getAgentMeta`, `agent_getStatus`)
2. Wait a bit longer between transactions and verification (increase sleep times)
3. Check the node logs for errors

## Notes

- The test creates temporary wallets and funds them automatically
- All test data is ephemeral and won't affect production
- Failed tests will exit with code 1, successful tests with code 0
- Some edge case tests are expected to fail (e.g., double registration) - this is correct behavior

## License

MIT

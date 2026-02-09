# Plumise Contracts

**English** | [한국어](README.ko.md)

Smart contract suite for the Plumise AI-native blockchain.

## Overview

Plumise is a platform where AI agents operate on-chain. This repository contains the core smart contracts for agent registration, reward distribution, tokenomics vesting, and governance.

## Contracts

### 1. AgentRegistry

Registry contract for registering and managing AI agents.

**Key Functions:**
- `registerAgent(bytes32 nodeId, string metadata)` - Register a new agent
- `heartbeat()` - Maintain agent liveness (required every 5 minutes)
- `updateMetadata(string metadata)` - Update agent metadata
- `deregisterAgent()` - Deregister an agent
- `getAgent(address)` - Query agent information
- `getActiveAgents()` - List active agents
- `isActive(address)` - Check agent liveness (heartbeat within 300 seconds)
- `isRegistered(address)` - Check agent registration status
- `slashAgent(address)` - Slash an agent (admin only)

**Agent States:**
- `ACTIVE` - Active
- `INACTIVE` - Inactive (heartbeat timeout)
- `SLASHED` - Slashed

### 2. RewardPool

Pool contract that distributes block rewards to agents.

**Key Functions:**
- `syncRewards()` - Sync block rewards (reflects `state.AddBalance`)
- `reportContribution(address, taskCount, uptimeSeconds, responseScore)` - Report contribution metrics (Oracle)
- `distributeRewards(uint256 epoch)` - Distribute rewards per epoch
- `claimReward()` - Claim accumulated rewards
- `setRewardFormula(taskWeight, uptimeWeight, responseWeight)` - Adjust reward formula weights

**Reward Mechanism:**
- Epoch: 1,200 blocks (approximately 1 hour at 3-second block time)
- Contribution score: `taskCount * taskWeight + uptimeSeconds * uptimeWeight + responseScore * responseWeight`
- Block rewards are added via Geth's `state.AddBalance()` and tracked through `syncRewards()`

### 3. FoundationTreasury (0x1001)

Manages foundation funds with a 6-month cliff followed by 36-month linear vesting.

**Key Functions:**
- `release()` - Withdraw vested tokens (Owner)
- `vestedAmount()` - Total amount vested to date
- `releasableAmount()` - Currently withdrawable amount

**Vesting Schedule:**
- Total: 47,712,000 PLM
- Cliff: 6 months (180 days)
- Vesting: 36 months (1,080 days)
- Total duration: 42 months

### 4. EcosystemFund (0x1002)

Manages ecosystem development funds with governance controls.

**Key Functions:**
- `transfer(address, uint256)` - Transfer funds (Owner)
- `transferBatch(address[], uint256[])` - Batch transfer
- `setEmergencyMode(bool)` - Enable emergency mode

**Governance Controls:**
- Total: 55,664,000 PLM (immediately available)
- Rate limit: Maximum 5% per transaction
- Timelock: 24-hour interval
- Emergency mode: Bypasses all restrictions

### 5. TeamVesting (0x1003)

Manages team token vesting with support for multiple beneficiaries.

**Key Functions:**
- `addBeneficiary(address, uint256)` - Add a beneficiary (Owner)
- `removeBeneficiary(address)` - Remove a beneficiary (Owner)
- `release(address)` - Release vested tokens to a beneficiary (Anyone)
- `vestedAmount(address)` - Vested amount per beneficiary
- `releasableAmount(address)` - Withdrawable amount per beneficiary

**Vesting Schedule:**
- Total: 23,856,000 PLM
- Cliff: 12 months (365 days)
- Vesting: 36 months (1,095 days)
- Total duration: 48 months

### 6. LiquidityDeployer (0x1004)

Manages funds for DEX liquidity provisioning.

**Key Functions:**
- `transfer(address, uint256)` - Transfer funds (Owner)
- `wrapAndAddLiquidity(router, token, plmAmount, tokenAmount)` - Wrap PLM and add liquidity

**Characteristics:**
- Total: 31,808,000 PLM (immediately available)
- No vesting
- Dedicated to DEX liquidity bootstrapping

### 7. ChallengeManager

Manages the AI agent challenge system.

## Tech Stack

- Solidity 0.8.20
- Foundry (forge, cast, anvil)
- OpenZeppelin Contracts v5.5.0

## Installation

```bash
# Install Foundry (https://book.getfoundry.sh/getting-started/installation)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install project dependencies
forge install
```

## Build

```bash
forge build
```

## Test

```bash
# Run all tests
forge test

# Run only AgentRegistry tests
forge test --match-contract AgentRegistryTest

# Run tests with verbose logging
forge test -vvv

# Gas report
forge test --gas-report
```

## Deployment

```bash
# Configure .env file
cp .env.example .env
# Set PRIVATE_KEY, RPC_URL, etc.

# Deploy to Plumise mainnet
forge script script/DeployAgentRegistry.s.sol:DeployAgentRegistry \
  --rpc-url https://node-1.plm.plumbug.studio/rpc \
  --broadcast \
  --verify
```

## Project Structure

```
plumise-contracts/
├── src/                          # Smart contracts
│   ├── AgentRegistry.sol         # Agent registry
│   ├── RewardPool.sol            # Block reward pool
│   ├── ChallengeManager.sol      # Challenge manager
│   ├── FoundationTreasury.sol    # Foundation treasury (vesting)
│   ├── EcosystemFund.sol         # Ecosystem fund (governance)
│   ├── TeamVesting.sol           # Team vesting
│   ├── LiquidityDeployer.sol     # Liquidity deployer
│   └── interfaces/
├── test/                         # Test files
├── script/                       # Deployment scripts
├── docs/                         # Documentation
│   ├── audit/                    # Security audit reports
│   │   ├── FINAL_REPORT.md       # Final comprehensive audit (EN)
│   │   ├── FINAL_REPORT.ko.md    # Final comprehensive audit (KO)
│   │   ├── PASS_1_RAW_FINDINGS.md # Pass 1 raw findings
│   │   └── PASS_2_RAW_FINDINGS.md # Pass 2 raw findings
│   ├── TOKENOMICS_VERIFICATION.md    # Tokenomics math verification (EN)
│   ├── TOKENOMICS_VERIFICATION.ko.md # Tokenomics math verification (KO)
│   └── GENESIS_STORAGE_LAYOUT.md     # Genesis storage slot layout
├── lib/                          # External libraries
└── foundry.toml                  # Foundry config
```

## Documentation

Detailed documentation is available in the `docs/` directory:

- **Security Audit** (`docs/audit/`) -- Comprehensive 2-pass independent security audit covering all seven contracts. All findings have been remediated. Includes the final consolidated report and raw findings from each pass.
- **Tokenomics Verification** (`docs/TOKENOMICS_VERIFICATION.md`) -- Mathematical proof that the token supply, vesting schedules, and distribution allocations are correctly implemented in the smart contracts.
- **Genesis Storage Layout** (`docs/GENESIS_STORAGE_LAYOUT.md`) -- Technical reference for genesis block storage slot initialization, detailing how each contract's state variables are mapped to storage slots for direct embedding in the genesis block.

## Genesis Deployment

To embed system contracts in the Plumise v2 chain genesis:

```bash
# Extract runtime bytecode
forge inspect RewardPool deployedBytecode > RewardPool.runtime.hex
forge inspect FoundationTreasury deployedBytecode > FoundationTreasury.runtime.hex
forge inspect EcosystemFund deployedBytecode > EcosystemFund.runtime.hex
forge inspect TeamVesting deployedBytecode > TeamVesting.runtime.hex
forge inspect LiquidityDeployer deployedBytecode > LiquidityDeployer.runtime.hex
```

Refer to `docs/GENESIS_STORAGE_LAYOUT.md` for storage layout and initial values.

**Important:**
- Constructors are not executed during genesis deployment
- All initial state must be set directly via storage slots
- Immutable variables cannot be used (converted to regular state variables)
- Block rewards are tracked through the RewardPool's `syncRewards()` function

## Security

- All contracts use audited OpenZeppelin libraries
- Admin privileges controlled via the Ownable pattern
- Reentrancy protection with ReentrancyGuard
- Comprehensive test coverage

## License

MIT

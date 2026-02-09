# Plumise v2 Genesis System Contracts - Storage Layout

이 문서는 genesis alloc에서 각 컨트랙트의 storage slots을 설정하기 위한 레이아웃 정보입니다.

## Owner Address (모든 컨트랙트 공통)
- Deployer: `0x5CEBec6EEeDc9040C72eA44fB1f8d28cD1079b8f`

## 1. RewardPool (0x0000000000000000000000000000000000001000)

### Storage Layout

| Slot | Name | Type | Initial Value | 설명 |
|------|------|------|---------------|------|
| 0 | _owner | address | 0x5CEBec6EEeDc9040C72eA44fB1f8d28cD1079b8f | Owner (Ownable) |
| 1 | agentRegistry | address | (AgentRegistry 주소) | AgentRegistry contract address |
| 2 | oracle | address | (Oracle 주소) | Oracle address |
| 3 | taskWeight | uint256 | 50 | Task weight (50%) |
| 4 | uptimeWeight | uint256 | 30 | Uptime weight (30%) |
| 5 | responseWeight | uint256 | 20 | Response weight (20%) |
| 6 | lastTrackedBalance | uint256 | 0 | Last tracked balance for syncRewards |
| 7 | contributions | mapping | - | Mapping (no init needed) |
| 8 | pendingRewards | mapping | - | Mapping (no init needed) |
| 9 | epochRewards | mapping | - | Mapping (no init needed) |
| 10 | epochContributions | mapping | - | Mapping (no init needed) |
| 11 | epochAgents | mapping | - | Mapping (no init needed) |
| 12 | epochAgentExists | mapping | - | Mapping (no init needed) |
| 13 | epochDistributed | mapping | - | Mapping (no init needed) |
| 14 | currentEpoch | uint256 | 0 | Current epoch number |
| 15 | deployBlock | uint256 | 0 | Genesis block number |

### Storage Values (Hex)

```
Slot 0: 0x0000000000000000000000005CEBec6EEeDc9040C72eA44fB1f8d28cD1079b8f (owner)
Slot 1: (AgentRegistry address - TBD)
Slot 2: (Oracle address - TBD)
Slot 3: 0x0000000000000000000000000000000000000000000000000000000000000032 (50)
Slot 4: 0x000000000000000000000000000000000000000000000000000000000000001e (30)
Slot 5: 0x0000000000000000000000000000000000000000000000000000000000000014 (20)
Slot 6: 0x0000000000000000000000000000000000000000000000000000000000000000 (0)
Slot 14: 0x0000000000000000000000000000000000000000000000000000000000000000 (0)
Slot 15: 0x0000000000000000000000000000000000000000000000000000000000000000 (0)
```

---

## 2. FoundationTreasury (0x0000000000000000000000000000000000001001)

### Storage Layout

| Slot | Name | Type | Initial Value | 설명 |
|------|------|------|---------------|------|
| 0 | _owner | address | 0x5CEBec6EEeDc9040C72eA44fB1f8d28cD1079b8f | Owner (Ownable) |
| 1 | totalAllocation | uint256 | 47712000000000000000000000 | 47,712,000 PLM (wei) |
| 2 | startTimestamp | uint256 | (Genesis timestamp) | Vesting start time |
| 3 | released | uint256 | 0 | Amount already released |

### Balance
- Initial balance: **47,712,000 PLM** (47712000000000000000000000 wei)

### Storage Values (Hex)

```
Slot 0: 0x0000000000000000000000005CEBec6EEeDc9040C72eA44fB1f8d28cD1079b8f (owner)
Slot 1: 0x00000000000000000000000000000000000009a3c1e08c44f6cfa0000000 (47712000 * 1e18)
Slot 2: (Genesis timestamp - TBD)
Slot 3: 0x0000000000000000000000000000000000000000000000000000000000000000 (0)
```

### Vesting Schedule
- Cliff: 6 months (180 days)
- Vesting: 36 months (1080 days)
- Total: 42 months

---

## 3. EcosystemFund (0x0000000000000000000000000000000000001002)

### Storage Layout

| Slot | Name | Type | Initial Value | 설명 |
|------|------|------|---------------|------|
| 0 | _owner | address | 0x5CEBec6EEeDc9040C72eA44fB1f8d28cD1079b8f | Owner (Ownable) |
| 1 | totalAllocation | uint256 | 55664000000000000000000000 | 55,664,000 PLM (wei) |
| 2 | lastTransferTimestamp | uint256 | 0 | Last transfer timestamp |
| 3 | emergencyMode | bool | false | Emergency mode status |

### Balance
- Initial balance: **55,664,000 PLM** (55664000000000000000000000 wei)

### Storage Values (Hex)

```
Slot 0: 0x0000000000000000000000005CEBec6EEeDc9040C72eA44fB1f8d28cD1079b8f (owner)
Slot 1: 0x00000000000000000000000000000000000b76f71ffbcf87df60000000 (55664000 * 1e18)
Slot 2: 0x0000000000000000000000000000000000000000000000000000000000000000 (0)
Slot 3: 0x0000000000000000000000000000000000000000000000000000000000000000 (false)
```

### Governance Controls
- Rate limit: 5% per transaction
- Timelock: 24 hours between transfers
- Emergency mode: Bypasses all limits

---

## 4. TeamVesting (0x0000000000000000000000000000000000001003)

### Storage Layout

| Slot | Name | Type | Initial Value | 설명 |
|------|------|------|---------------|------|
| 0 | _owner | address | 0x5CEBec6EEeDc9040C72eA44fB1f8d28cD1079b8f | Owner (Ownable) |
| 1 | totalAllocation | uint256 | 23856000000000000000000000 | 23,856,000 PLM (wei) |
| 2 | startTimestamp | uint256 | (Genesis timestamp) | Vesting start time |
| 3 | beneficiaries | mapping | - | Mapping (no init needed) |
| 4 | beneficiaryList | address[] | [] | Empty array initially |
| 5 | isBeneficiary | mapping | - | Mapping (no init needed) |
| 6 | totalAllocated | uint256 | 0 | Total allocated to beneficiaries |

### Balance
- Initial balance: **23,856,000 PLM** (23856000000000000000000000 wei)

### Storage Values (Hex)

```
Slot 0: 0x0000000000000000000000005CEBec6EEeDc9040C72eA44fB1f8d28cD1079b8f (owner)
Slot 1: 0x0000000000000000000000000000000000004f3a54d9a9be65e80000000 (23856000 * 1e18)
Slot 2: (Genesis timestamp - TBD)
Slot 4: 0x0000000000000000000000000000000000000000000000000000000000000000 (array length 0)
Slot 6: 0x0000000000000000000000000000000000000000000000000000000000000000 (0)
```

### Vesting Schedule
- Cliff: 12 months (365 days)
- Vesting: 36 months (1095 days)
- Total: 48 months

---

## 5. LiquidityDeployer (0x0000000000000000000000000000000000001004)

### Storage Layout

| Slot | Name | Type | Initial Value | 설명 |
|------|------|------|---------------|------|
| 0 | _owner | address | 0x5CEBec6EEeDc9040C72eA44fB1f8d28cD1079b8f | Owner (Ownable) |
| 1 | totalAllocation | uint256 | 31808000000000000000000000 | 31,808,000 PLM (wei) |

### Balance
- Initial balance: **31,808,000 PLM** (31808000000000000000000000 wei)

### Storage Values (Hex)

```
Slot 0: 0x0000000000000000000000005CEBec6EEeDc9040C72eA44fB1f8d28cD1079b8f (owner)
Slot 1: 0x000000000000000000000000000000000000069e133c3ef5e64820000000 (31808000 * 1e18)
```

### Usage
- Immediately available (no vesting)
- For DEX liquidity provision

---

## Genesis Alloc Summary

### Total Supply: 159,040,000 PLM

| Contract | Address | Balance | Notes |
|----------|---------|---------|-------|
| RewardPool | 0x1000 | 0 | Receives block rewards |
| FoundationTreasury | 0x1001 | 47,712,000 | 6mo cliff + 36mo vesting |
| EcosystemFund | 0x1002 | 55,664,000 | Governance-managed |
| TeamVesting | 0x1003 | 23,856,000 | 12mo cliff + 36mo vesting |
| LiquidityDeployer | 0x1004 | 31,808,000 | Immediately available |

### Compilation Info
- Solidity: 0.8.20
- EVM: paris
- Optimizer: enabled (default)
- Runtime bytecode를 `code` 필드에 설정
- Storage values를 `storage` 필드에 설정

### Runtime Bytecode 추출

```bash
# 각 컨트랙트의 runtime bytecode 추출
forge inspect RewardPool deployedBytecode > RewardPool.runtime.hex
forge inspect FoundationTreasury deployedBytecode > FoundationTreasury.runtime.hex
forge inspect EcosystemFund deployedBytecode > EcosystemFund.runtime.hex
forge inspect TeamVesting deployedBytecode > TeamVesting.runtime.hex
forge inspect LiquidityDeployer deployedBytecode > LiquidityDeployer.runtime.hex
```

### Genesis JSON Example

```json
{
  "0x0000000000000000000000000000000000001001": {
    "code": "(runtime bytecode hex)",
    "balance": "0x00000000000000000000000000000000000009a3c1e08c44f6cfa0000000",
    "storage": {
      "0x0000000000000000000000000000000000000000000000000000000000000000": "0x0000000000000000000000005CEBec6EEeDc9040C72eA44fB1f8d28cD1079b8f",
      "0x0000000000000000000000000000000000000000000000000000000000000001": "0x00000000000000000000000000000000000009a3c1e08c44f6cfa0000000",
      "0x0000000000000000000000000000000000000000000000000000000000000002": "(genesis timestamp)",
      "0x0000000000000000000000000000000000000000000000000000000000000003": "0x0000000000000000000000000000000000000000000000000000000000000000"
    }
  }
}
```

---

## 주의사항

1. **Constructor 미실행**: Genesis 배포 시 constructor가 실행되지 않으므로 모든 초기 상태를 storage로 설정해야 합니다.

2. **immutable 제거**: 모든 immutable 변수를 일반 state variable로 변경했습니다.

3. **Timestamp 설정**: `startTimestamp`는 genesis 블록의 timestamp로 설정해야 합니다.

4. **AgentRegistry 주소**: RewardPool의 slot 1에 AgentRegistry 컨트랙트 주소를 설정해야 합니다.

5. **Oracle 주소**: RewardPool의 slot 2에 Oracle 주소를 설정해야 합니다.

6. **블록 보상 동기화**: RewardPool의 `syncRewards()` 함수를 주기적으로 호출하여 `state.AddBalance()`로 추가된 블록 보상을 추적해야 합니다.

---

## Verification

Genesis 배포 후 각 컨트랙트의 상태를 확인:

```bash
# Owner 확인
cast call 0x1001 "owner()(address)" --rpc-url <RPC>

# Balance 확인
cast balance 0x1001 --rpc-url <RPC>

# Total allocation 확인
cast call 0x1001 "totalAllocation()(uint256)" --rpc-url <RPC>

# Vesting 정보 확인
cast call 0x1001 "vestedAmount()(uint256)" --rpc-url <RPC>
cast call 0x1001 "releasableAmount()(uint256)" --rpc-url <RPC>
```

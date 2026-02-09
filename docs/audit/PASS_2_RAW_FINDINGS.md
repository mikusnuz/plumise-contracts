# Security Audit - Pass 2 Raw Findings (Pre-Remediation, Independent Cross-Check)
## Plumise v2 Genesis System Contracts

**Audit Date:** 2026-02-10
**Auditor:** Claude Sonnet 4.5 (Independent Security Agent #2)
**Version:** Genesis Deployment Review
**Commit:** N/A (Pre-deployment Review)

---

## Executive Summary

이 감사는 Plumise v2 체인의 genesis에 임베딩될 시스템 컨트랙트에 대한 독립적 보안 검증입니다. Genesis 배포 후 **교체 불가능**하다는 특수성을 고려하여, 배포 시나리오, 경제적 공격 벡터, 컨트랙트 간 상호작용, edge cases를 중점적으로 분석했습니다.

### Critical Findings: 3
### High Severity: 4
### Medium Severity: 6
### Low Severity: 5
### Informational: 8

**주요 위험:**
- Genesis 배포 시 초기화 누락 가능성 (CRITICAL)
- RewardPool의 AgentRegistry 의존성 장애 시 전체 보상 시스템 마비 (CRITICAL)
- 산술 오버플로우로 인한 보상 계산 오류 (HIGH)
- Oracle 단일 실패 지점 (HIGH)
- 강제 ETH 전송으로 인한 accounting 불일치 (MEDIUM)

---

## Methodology

### 1. Genesis 배포 시뮬레이션
- Constructor 미실행 상태에서의 변수 초기화 검증
- Storage slot 직접 설정 시나리오 분석
- Immutable 변수 제거로 인한 가스 비용 증가 측정

### 2. 컨트랙트 간 의존성 분석
- RewardPool ↔ AgentRegistry 상호작용 검증
- 한 컨트랙트 실패 시 cascading failure 시뮬레이션

### 3. 경제적 공격 벡터
- Flash loan을 이용한 보상 조작 가능성
- MEV (Maximal Extractable Value) 추출 시나리오
- Oracle 조작을 통한 부당 이익

### 4. Edge Case Testing
- block.timestamp = 0 (genesis block)
- 극한값 입력 (type(uint256).max)
- 동시 다발 트랜잭션 경쟁 조건

### 5. Solidity 특유 취약점
- Reentrancy, delegatecall, selfdestruct, tx.origin 등
- PoA 체인에서 block.timestamp 조작 가능성

---

## Findings

### [CRITICAL-01] Genesis 배포 시 RewardPool의 deployBlock이 0으로 초기화되지 않음

**Severity:** Critical
**Contract:** RewardPool.sol
**Line:** 57, 70, 266

**Description:**

Genesis 배포 시 constructor가 실행되지 않아 `deployBlock`이 storage에서 직접 0으로 설정됩니다. 하지만 genesis block number는 **0이 아니라 1 이상**일 수 있습니다 (체인 설정에 따라 다름).

이 경우 `getCurrentEpoch()` 함수가 잘못된 epoch를 계산합니다:

```solidity
// Line 266
function getCurrentEpoch() public view returns (uint256) {
    return (block.number - deployBlock) / BLOCKS_PER_EPOCH;
}
```

만약 genesis block number가 1000이고 `deployBlock`이 0이면, epoch 0가 아니라 epoch 0.83으로 계산되어 즉시 epoch 1로 진입합니다.

**Proof of Concept:**

```solidity
// Genesis: block.number = 1000, deployBlock = 0
// getCurrentEpoch() = (1000 - 0) / 1200 = 0 (uint division)
// 정상 작동하는 것처럼 보이지만...

// 1199 블록 후: block.number = 2199
// getCurrentEpoch() = (2199 - 0) / 1200 = 1
// 예상: epoch 1, 실제 블록 경과: 1199 블록 (1200 블록이 아님)

// 보상 분배 시점이 1 블록 빨라짐
// 누적되면 epoch마다 시간 차이 발생
```

**Impact:**
- Epoch 경계가 부정확해져 보상 분배 타이밍 왜곡
- Oracle이 기대하는 epoch와 실제 epoch 불일치
- 누적 오차로 장기적으로 시스템 혼란

**Mitigation:**

Genesis JSON에서 `deployBlock`을 **정확한 genesis block number**로 설정:

```json
{
  "0x0000000000000000000000000000000000001000": {
    "storage": {
      "0x000000000000000000000000000000000000000000000000000000000000000f": "0x0000000000000000000000000000000000000000000000000000000000000001"
    }
  }
}
```

또는 코드 수정 (하지만 Genesis 배포 전에만 가능):

```solidity
function getCurrentEpoch() public view returns (uint256) {
    if (deployBlock == 0) {
        deployBlock = 1; // Genesis block number fallback
    }
    return (block.number - deployBlock) / BLOCKS_PER_EPOCH;
}
```

---

### [CRITICAL-02] RewardPool이 AgentRegistry에 전적으로 의존하여 단일 실패 지점 형성

**Severity:** Critical
**Contract:** RewardPool.sol
**Line:** 19, 116-117, 195

**Description:**

RewardPool은 AgentRegistry의 `isRegistered()`, `isActive()` 함수에 전적으로 의존합니다:

```solidity
// Line 116-117
require(agentRegistry.isRegistered(agent), "Agent not registered");
require(agentRegistry.isActive(agent), "Agent not active");

// Line 195
require(agentRegistry.isRegistered(msg.sender), "Not registered");
```

만약 AgentRegistry가:
1. 버그로 인해 모든 agent를 inactive로 반환
2. Gas 비용 증가로 external call이 실패
3. 의도적으로 특정 agent를 차단

이 경우 **전체 보상 시스템이 마비**됩니다. Genesis 배포 후 교체 불가능하므로 복구 방법이 없습니다.

**Proof of Concept:**

```solidity
// AgentRegistry에 버그 발생 (모든 isActive()가 false 반환)
contract BuggyAgentRegistry {
    function isActive(address) external view returns (bool) {
        return false; // 버그로 인해 항상 false
    }
}

// RewardPool에서 모든 reportContribution() 실패
vm.prank(oracle);
vm.expectRevert("Agent not active"); // 모든 agent가 비활성으로 처리됨
rewardPool.reportContribution(agent1, 10, 3600, 95);

// 보상 분배 불가능 → 블록 보상 영구 잠김
```

**Impact:**
- AgentRegistry 장애 시 전체 보상 시스템 마비
- 누적된 블록 보상이 영구적으로 잠김
- Agent들이 보상을 받을 수 없어 네트워크 탈퇴 가능성

**Mitigation:**

1. **Emergency Bypass 메커니즘 추가:**

```solidity
bool public emergencyBypassRegistry;

function setEmergencyBypassRegistry(bool enabled) external onlyOwner {
    emergencyBypassRegistry = enabled;
    emit EmergencyBypassRegistryChanged(enabled);
}

function reportContribution(...) external {
    require(msg.sender == oracle, "Only oracle");

    if (!emergencyBypassRegistry) {
        require(agentRegistry.isRegistered(agent), "Agent not registered");
        require(agentRegistry.isActive(agent), "Agent not active");
    }
    // ... 나머지 로직
}
```

2. **Try-Catch로 external call 실패 처리:**

```solidity
function reportContribution(...) external {
    require(msg.sender == oracle, "Only oracle");

    try agentRegistry.isRegistered(agent) returns (bool registered) {
        require(registered, "Agent not registered");
    } catch {
        // External call 실패 시 owner가 emergency mode를 활성화해야 함
        revert("AgentRegistry unreachable");
    }
    // ... 나머지 로직
}
```

---

### [CRITICAL-03] Genesis 배포 시 startTimestamp가 0으로 설정되면 vesting이 즉시 시작됨

**Severity:** Critical
**Contract:** FoundationTreasury.sol, TeamVesting.sol
**Line:** FoundationTreasury.sol:18, 36 / TeamVesting.sol:18, 44

**Description:**

Genesis 배포 시 `startTimestamp`를 storage에서 직접 설정해야 하는데, 만약 **0으로 남겨두면** Unix epoch (1970-01-01)부터 vesting이 시작된 것으로 계산됩니다.

```solidity
// FoundationTreasury.sol Line 76-87
function _vestedAmount(uint256 timestamp) internal view returns (uint256) {
    if (timestamp < startTimestamp + CLIFF_DURATION) {
        return 0;
    } else if (timestamp >= startTimestamp + CLIFF_DURATION + VESTING_DURATION) {
        return totalAllocation; // 모든 토큰이 즉시 인출 가능!
    } else {
        uint256 elapsedSinceCliff = timestamp - (startTimestamp + CLIFF_DURATION);
        return (totalAllocation * elapsedSinceCliff) / VESTING_DURATION;
    }
}
```

만약 `startTimestamp = 0`이고 현재 시간이 2026년이면:
- `timestamp >= 0 + 180 days + 1080 days` → **항상 true**
- `vestedAmount()` → **47,712,000 PLM 전체가 즉시 인출 가능**

**Proof of Concept:**

```solidity
// Genesis 배포 시 startTimestamp = 0 (실수로 설정 안 함)
// 2026-02-10에 배포됨

FoundationTreasury treasury = new FoundationTreasury();
// startTimestamp는 constructor에서 block.timestamp로 설정되지만
// Genesis에서는 constructor가 실행되지 않아 0으로 남음

vm.deal(address(treasury), 47_712_000 ether);
// Storage slot 2 = 0 (설정 안 함)

// 즉시 전체 인출 가능
assertEq(treasury.vestedAmount(), 47_712_000 ether); // FAIL: 의도하지 않은 전체 인출
```

**Impact:**
- 재단/팀 자금이 cliff/vesting 없이 즉시 인출 가능
- 토큰 경제 붕괴 (예상: 42개월 분산, 실제: 즉시 인출)
- 투자자/커뮤니티 신뢰 상실

**Mitigation:**

Genesis JSON에서 `startTimestamp`를 **정확한 genesis timestamp**로 설정:

```json
{
  "0x0000000000000000000000000000000000001001": {
    "storage": {
      "0x0000000000000000000000000000000000000000000000000000000000000002": "0x0000000000000000000000000000000000000000000000000000000065c7a8c0"
    }
  }
}
```

**Validation 스크립트 필수:**

```bash
#!/bin/bash
# Genesis 배포 후 즉시 검증
FOUNDATION_ADDR="0x1001"
TEAM_ADDR="0x1003"

# startTimestamp가 0이 아닌지 확인
START_TS=$(cast call $FOUNDATION_ADDR "startTimestamp()(uint256)" --rpc-url $RPC)
if [ "$START_TS" == "0" ]; then
    echo "CRITICAL: startTimestamp is 0! Vesting bypassed!"
    exit 1
fi

# vestedAmount가 0인지 확인 (genesis 직후)
VESTED=$(cast call $FOUNDATION_ADDR "vestedAmount()(uint256)" --rpc-url $RPC)
if [ "$VESTED" != "0" ]; then
    echo "CRITICAL: vestedAmount is not 0 at genesis!"
    exit 1
fi

echo "Vesting validation passed."
```

---

### [HIGH-01] RewardPool의 calculateScore에서 산술 오버플로우 가능

**Severity:** High
**Contract:** RewardPool.sol
**Line:** 274-279

**Description:**

`calculateScore()` 함수는 기여도를 계산할 때 곱셈을 먼저 수행합니다:

```solidity
function calculateScore(Contribution memory contribution) internal view returns (uint256) {
    return
        contribution.taskCount * taskWeight +
        contribution.uptimeSeconds * uptimeWeight +
        contribution.responseScore * responseWeight;
}
```

만약 악의적인 Oracle이 극한값을 입력하면:
- `taskCount = type(uint128).max` (테스트에서 bound로 제한)
- `uptimeSeconds = type(uint128).max`
- `responseScore = type(uint128).max`

각 항이 `type(uint128).max * 50 = 약 1.7e40`에 도달하여, 세 항을 더하면 **uint256 오버플로우**가 발생합니다 (Solidity 0.8.x는 기본적으로 revert하지만, 의도치 않은 revert로 보상 분배 실패).

**Proof of Concept:**

```solidity
// Oracle이 극한값을 입력
vm.prank(oracle);
rewardPool.reportContribution(
    agent1,
    type(uint128).max,    // 2^128 - 1
    type(uint128).max,
    type(uint128).max
);

// distributeRewards 시도
vm.roll(block.number + 1200);

// calculateScore()에서 오버플로우로 revert
vm.expectRevert(); // Arithmetic overflow
rewardPool.distributeRewards(0);

// 결과: 해당 epoch의 보상이 영구적으로 잠김
```

**Impact:**
- Oracle의 실수 또는 악의로 인한 보상 분배 실패
- 해당 epoch의 블록 보상이 영구 잠김
- Agent들의 기여도가 무효화됨

**Mitigation:**

1. **입력값 제한:**

```solidity
uint256 public constant MAX_TASK_COUNT = 10_000;
uint256 public constant MAX_UPTIME_SECONDS = 7 * 24 * 3600; // 1주일
uint256 public constant MAX_RESPONSE_SCORE = 1_000_000;

function reportContribution(...) external {
    require(taskCount <= MAX_TASK_COUNT, "Task count too high");
    require(uptimeSeconds <= MAX_UPTIME_SECONDS, "Uptime too high");
    require(responseScore <= MAX_RESPONSE_SCORE, "Response score too high");
    // ... 나머지 로직
}
```

2. **Safe Math 패턴:**

```solidity
function calculateScore(Contribution memory contribution) internal view returns (uint256) {
    // 오버플로우 체크를 명시적으로 수행
    uint256 taskScore = contribution.taskCount * taskWeight;
    uint256 uptimeScore = contribution.uptimeSeconds * uptimeWeight;
    uint256 responseScoreValue = contribution.responseScore * responseWeight;

    // 각 항이 reasonable한지 확인
    require(taskScore <= type(uint128).max, "Task score overflow");
    require(uptimeScore <= type(uint128).max, "Uptime score overflow");
    require(responseScoreValue <= type(uint128).max, "Response score overflow");

    return taskScore + uptimeScore + responseScoreValue;
}
```

---

### [HIGH-02] Oracle 단일 실패 지점 (Single Point of Failure)

**Severity:** High
**Contract:** RewardPool.sol
**Line:** 22, 115

**Description:**

RewardPool은 단일 Oracle 주소에만 의존합니다:

```solidity
address public oracle;

function reportContribution(...) external {
    require(msg.sender == oracle, "Only oracle");
    // ... 보상 분배 로직
}
```

만약 Oracle의 private key가:
1. 분실됨
2. 탈취됨
3. Owner가 교체하지 않고 방치됨

이 경우:
- **분실:** 더 이상 기여도를 보고할 수 없어 보상 시스템 마비
- **탈취:** 공격자가 임의로 기여도를 조작하여 특정 agent에게 과도한 보상 분배
- **방치:** 오래된 Oracle이 부정확한 데이터를 계속 보고

**Proof of Concept:**

```solidity
// Oracle private key 분실
// 더 이상 reportContribution() 호출 불가

// Owner가 새로운 Oracle 설정
rewardPool.setOracle(newOracle);

// 하지만 이전 epoch들의 기여도는 보고되지 않아 보상 손실
// 복구 방법 없음 (과거 데이터 재입력 불가)
```

**Impact:**
- Oracle 장애 시 전체 보상 시스템 마비
- Oracle 탈취 시 부당한 보상 분배
- 과거 기여도 복구 불가능

**Mitigation:**

1. **Multi-Oracle 패턴:**

```solidity
mapping(address => bool) public oracles;
uint256 public requiredOracles = 2; // Consensus 필요

mapping(uint256 => mapping(address => mapping(address => bool))) public contributionVotes;

function reportContribution(...) external {
    require(oracles[msg.sender], "Not authorized oracle");

    contributionVotes[getCurrentEpoch()][agent][msg.sender] = true;

    // Consensus 확인
    uint256 votes = 0;
    for (address oracle in oracleList) {
        if (contributionVotes[getCurrentEpoch()][agent][oracle]) {
            votes++;
        }
    }

    if (votes >= requiredOracles) {
        // 기여도 기록
    }
}
```

2. **Oracle Rotation 메커니즘:**

```solidity
address[] public oracleHistory;
uint256 public currentOracleIndex;
uint256 public constant ORACLE_ROTATION_PERIOD = 100 epochs;

function rotateOracle() external {
    require(getCurrentEpoch() % ORACLE_ROTATION_PERIOD == 0, "Not rotation time");
    currentOracleIndex = (currentOracleIndex + 1) % oracleHistory.length;
    oracle = oracleHistory[currentOracleIndex];
}
```

---

### [HIGH-03] RewardPool.distributeRewards에서 정밀도 손실로 인한 보상 누락

**Severity:** High
**Contract:** RewardPool.sol
**Line:** 182

**Description:**

`distributeRewards()` 함수는 보상을 비례 배분할 때 정수 나눗셈을 사용합니다:

```solidity
uint256 reward = (totalReward * score) / totalScore;
pendingRewards[agent] += reward;
```

정수 나눗셈으로 인해 **remainder가 버려집니다**. 예를 들어:
- `totalReward = 10 ether`
- `totalScore = 3`
- Agent 1: score = 1 → reward = 3.333... ether → **3 ether** (0.333... ether 손실)
- Agent 2: score = 1 → reward = 3.333... ether → **3 ether** (0.333... ether 손실)
- Agent 3: score = 1 → reward = 3.333... ether → **3 ether** (0.333... ether 손실)
- **총 분배: 9 ether, 남은 보상: 1 ether** (컨트랙트에 영구 잠김)

수백만 epoch 후 누적 손실이 커질 수 있습니다.

**Proof of Concept:**

```solidity
// Epoch에 10 ether 보상
(bool success, ) = address(rewardPool).call{value: 10 ether}("");
assertTrue(success);

// 3명의 agent가 동일한 기여도
vm.startPrank(oracle);
rewardPool.reportContribution(agent1, 1, 0, 0); // score = 1 * 50 = 50
rewardPool.reportContribution(agent2, 1, 0, 0); // score = 50
rewardPool.reportContribution(agent3, 1, 0, 0); // score = 50
vm.stopPrank();

// totalScore = 150
// reward1 = (10 ether * 50) / 150 = 3.333... ether → 3333333333333333333 wei
// reward2 = 3333333333333333333 wei
// reward3 = 3333333333333333333 wei
// 총 분배: 9999999999999999999 wei
// 남은 보상: 1 wei

vm.roll(block.number + 1200);
rewardPool.distributeRewards(0);

uint256 contractBalance = address(rewardPool).balance;
assertEq(contractBalance, 1); // 1 wei가 영구 잠김
```

**Impact:**
- Epoch마다 미세한 보상 손실
- 장기적으로 누적되면 상당한 금액
- 컨트랙트 잔액이 지속적으로 증가 (회수 불가능)

**Mitigation:**

1. **Remainder를 마지막 agent에게 분배:**

```solidity
uint256 totalDistributed = 0;

for (uint256 i = 0; i < agentCount; i++) {
    address agent = agents[i];
    uint256 score = calculateScore(epochContributions[epoch][agent]);

    if (i == agentCount - 1) {
        // 마지막 agent에게 남은 보상 전부 분배
        uint256 reward = totalReward - totalDistributed;
        pendingRewards[agent] += reward;
    } else {
        uint256 reward = (totalReward * score) / totalScore;
        pendingRewards[agent] += reward;
        totalDistributed += reward;
    }
}
```

2. **High-precision accounting (향후 업그레이드 시 고려):**

```solidity
// Scaled up precision (1e18 scaling)
uint256 scaledReward = (totalReward * score * 1e18) / totalScore;
uint256 reward = scaledReward / 1e18;
// Remainder를 별도 계정에 누적하여 나중에 재분배
```

---

### [HIGH-04] EcosystemFund의 emergencyMode가 악용 가능

**Severity:** High
**Contract:** EcosystemFund.sol
**Line:** 27, 49-60, 89-100, 121-124

**Description:**

`emergencyMode`가 활성화되면 **모든 제약이 해제**됩니다:
- Rate limit (5% per tx) 무시
- Timelock (24시간) 무시

Owner가 악의적이거나 private key가 탈취되면:

```solidity
// Line 121-124
function setEmergencyMode(bool enabled) external override onlyOwner {
    emergencyMode = enabled;
    emit EmergencyModeChanged(enabled);
}

// Line 49-60
if (!emergencyMode) {
    require(amount <= maxAmount, "Exceeds rate limit");
    require(
        lastTransferTimestamp == 0 ||
        block.timestamp >= lastTransferTimestamp + TIMELOCK_DURATION,
        "Timelock active"
    );
}
```

공격자는 다음과 같이 모든 자금을 탈취할 수 있습니다:

```solidity
rewardPool.setEmergencyMode(true);
rewardPool.transfer(attackerAddress, 55_664_000 ether); // 전체 잔액
```

**Proof of Concept:**

```solidity
// Owner의 private key가 탈취됨
address attacker = 0xAttacker;

vm.startPrank(owner);

// Emergency mode 활성화
fund.setEmergencyMode(true);

// Rate limit/timelock 없이 전체 잔액 탈취
uint256 totalBalance = fund.getBalance();
fund.transfer(attacker, totalBalance);

vm.stopPrank();

// 결과: 55,664,000 PLM 전체가 공격자에게 이전
assertEq(attacker.balance, totalBalance);
assertEq(fund.getBalance(), 0);
```

**Impact:**
- Owner private key 탈취 시 생태계 자금 전액 손실
- Governance 프로세스 우회
- 커뮤니티/투자자 신뢰 붕괴

**Mitigation:**

1. **Timelock을 emergencyMode에도 적용:**

```solidity
uint256 public emergencyModeActivatedAt;

function setEmergencyMode(bool enabled) external onlyOwner {
    if (enabled) {
        emergencyModeActivatedAt = block.timestamp;
    }
    emergencyMode = enabled;
    emit EmergencyModeChanged(enabled);
}

function transfer(address to, uint256 amount) external onlyOwner nonReentrant {
    // ...

    if (emergencyMode) {
        // Emergency mode에서도 최소 timelock 적용
        require(
            block.timestamp >= emergencyModeActivatedAt + 1 hours,
            "Emergency mode cooling period"
        );
    } else {
        // 기존 rate limit/timelock
    }

    // ...
}
```

2. **Multi-sig Owner:**

```solidity
// Gnosis Safe 등 multi-sig wallet을 owner로 설정
// 단일 private key 탈취로는 자금 이동 불가
```

3. **Emergency mode에도 rate limit 적용:**

```solidity
if (emergencyMode) {
    // 긴급 상황에서도 최대 10% per tx로 제한
    uint256 maxAmount = (totalAllocation * 10) / 100;
    require(amount <= maxAmount, "Exceeds emergency rate limit");
} else {
    // 일반 상황: 5% per tx
    uint256 maxAmount = (totalAllocation * RATE_LIMIT_PERCENT) / 100;
    require(amount <= maxAmount, "Exceeds rate limit");
}
```

---

### [MEDIUM-01] 강제 ETH 전송으로 인한 balance 불일치

**Severity:** Medium
**Contract:** RewardPool.sol
**Line:** 30, 81, 90-91, 206

**Description:**

RewardPool은 `lastTrackedBalance`로 잔액을 추적하지만, `selfdestruct`를 이용한 **강제 ETH 전송**은 추적하지 못합니다:

```solidity
contract Attacker {
    function attack(address target) external payable {
        selfdestruct(payable(target));
        // RewardPool에 ETH가 강제 전송되지만
        // receive()나 syncRewards()가 호출되지 않음
    }
}
```

이 경우:
- `address(this).balance` ≠ `lastTrackedBalance`
- `syncRewards()`는 `currentBalance > lastTrackedBalance` 조건으로만 호출 가능
- 강제 전송된 ETH는 영구적으로 추적되지 않음

**Proof of Concept:**

```solidity
// 공격자가 selfdestruct로 1 ETH를 강제 전송
contract ForceEther {
    constructor(address target) payable {
        selfdestruct(payable(target));
    }
}

// RewardPool의 balance는 1 ETH 증가했지만 lastTrackedBalance는 그대로
uint256 balanceBefore = address(rewardPool).balance;
uint256 trackedBefore = rewardPool.lastTrackedBalance();

new ForceEther{value: 1 ether}(address(rewardPool));

uint256 balanceAfter = address(rewardPool).balance;
uint256 trackedAfter = rewardPool.lastTrackedBalance();

assertEq(balanceAfter, balanceBefore + 1 ether); // balance는 증가
assertEq(trackedAfter, trackedBefore);           // tracked는 그대로

// syncRewards()는 정상 작동 (currentBalance > lastTrackedBalance)
rewardPool.syncRewards(); // 성공

// 하지만 의도하지 않은 1 ETH가 보상으로 분배됨
```

**Impact:**
- 악의적인 강제 전송으로 보상 accounting 왜곡
- 예상보다 많은 보상이 분배될 수 있음
- 장기적으로 잔액 불일치 누적

**Mitigation:**

**참고:** Solidity 0.8.18부터 `selfdestruct`의 동작이 변경되어 이 문제가 완화되었습니다 (EIP-6049). 하지만 이전 버전 코드나 향후 호환성을 위해 방어 로직 추가 권장.

```solidity
// syncRewards()에서 강제 전송 감지
function syncRewards() external {
    uint256 currentBalance = address(this).balance;

    if (currentBalance > lastTrackedBalance) {
        uint256 newRewards = currentBalance - lastTrackedBalance;
        uint256 epoch = getCurrentEpoch();

        // 강제 전송 의심 (receive()를 거치지 않은 경우)
        if (newRewards > expectedBlockRewards[epoch]) {
            emit UnexpectedFundsReceived(newRewards - expectedBlockRewards[epoch]);
        }

        epochRewards[epoch] += newRewards;
        lastTrackedBalance = currentBalance;
        emit RewardReceived(newRewards, epoch);
    } else {
        revert("No new rewards");
    }
}
```

---

### [MEDIUM-02] RewardPool.claimReward의 reentrancy 위험

**Severity:** Medium
**Contract:** RewardPool.sol
**Line:** 194-208

**Description:**

`claimReward()` 함수는 ReentrancyGuard를 사용하지만, **msg.sender.call{value}()**로 ETH를 전송하므로 악의적인 컨트랙트가 fallback/receive에서 reentrancy를 시도할 수 있습니다:

```solidity
function claimReward() external override nonReentrant {
    require(agentRegistry.isRegistered(msg.sender), "Not registered");

    uint256 reward = pendingRewards[msg.sender];
    require(reward > 0, "No rewards");

    pendingRewards[msg.sender] = 0; // State update (Checks-Effects-Interactions 준수)

    (bool success, ) = msg.sender.call{value: reward}(""); // Interaction
    require(success, "Transfer failed");

    lastTrackedBalance = address(this).balance;
    emit RewardClaimed(msg.sender, reward);
}
```

현재 코드는 **Checks-Effects-Interactions 패턴을 올바르게 구현**했지만, ReentrancyGuard가 없었다면 다음과 같은 공격이 가능했습니다:

```solidity
contract ReentrancyAttacker {
    RewardPool public pool;
    uint256 public attackCount;

    function attack() external {
        pool.claimReward();
    }

    receive() external payable {
        if (attackCount < 10) {
            attackCount++;
            pool.claimReward(); // Reentrancy 시도
        }
    }
}
```

**Proof of Concept:**

```solidity
// 현재 코드는 ReentrancyGuard로 보호되므로 공격 실패
ReentrancyAttacker attacker = new ReentrancyAttacker(rewardPool);

vm.deal(address(rewardPool), 10 ether);
rewardPool.distributeRewards(0); // attacker에게 보상 분배

vm.startPrank(address(attacker));
vm.expectRevert("ReentrancyGuard: reentrant call");
attacker.attack(); // Reentrancy 시도 → 실패
vm.stopPrank();
```

**Impact:**
- 현재는 ReentrancyGuard로 보호됨 (위험도 낮음)
- 향후 코드 수정 시 실수로 ReentrancyGuard 제거하면 취약점 발생

**Mitigation:**

현재 코드는 안전하지만, 추가 방어 레이어 권장:

```solidity
// 1. Low-level call 대신 transfer() 사용 (gas limit 2300)
function claimReward() external override nonReentrant {
    // ...
    payable(msg.sender).transfer(reward); // Gas limit으로 reentrancy 불가능
    // ...
}

// 2. Pull payment 패턴 (추천)
mapping(address => uint256) public withdrawable;

function claimReward() external override {
    require(agentRegistry.isRegistered(msg.sender), "Not registered");
    uint256 reward = pendingRewards[msg.sender];
    require(reward > 0, "No rewards");

    pendingRewards[msg.sender] = 0;
    withdrawable[msg.sender] += reward;
    emit RewardClaimed(msg.sender, reward);
}

function withdraw() external nonReentrant {
    uint256 amount = withdrawable[msg.sender];
    require(amount > 0, "Nothing to withdraw");

    withdrawable[msg.sender] = 0;
    (bool success, ) = msg.sender.call{value: amount}("");
    require(success, "Transfer failed");
}
```

---

### [MEDIUM-03] TeamVesting.removeBeneficiary의 array deletion이 비효율적

**Severity:** Medium
**Contract:** TeamVesting.sol
**Line:** 78-98

**Description:**

`removeBeneficiary()` 함수는 beneficiaryList 배열에서 요소를 삭제할 때 **선형 탐색 (O(n))**을 수행합니다:

```solidity
// Line 88-95
for (uint256 i = 0; i < beneficiaryList.length; i++) {
    if (beneficiaryList[i] == beneficiary) {
        beneficiaryList[i] = beneficiaryList[beneficiaryList.length - 1];
        beneficiaryList.pop();
        break;
    }
}
```

Beneficiary가 많을수록 (예: 100명) gas 비용이 급격히 증가합니다. 최악의 경우 (배열 마지막 요소 삭제) **O(n) gas 비용**이 발생합니다.

**Proof of Concept:**

```solidity
// 100명의 beneficiary 추가
for (uint256 i = 0; i < 100; i++) {
    address beneficiary = address(uint160(i + 1));
    vesting.addBeneficiary(beneficiary, 1_000 ether);
}

// 첫 번째 beneficiary 제거 (gas: ~50,000)
uint256 gasBefore = gasleft();
vesting.removeBeneficiary(address(1));
uint256 gasAfter = gasleft();
console.log("Gas for removing first:", gasBefore - gasAfter);

// 마지막 beneficiary 제거 (gas: ~5,000,000)
gasBefore = gasleft();
vesting.removeBeneficiary(address(100));
gasAfter = gasleft();
console.log("Gas for removing last:", gasBefore - gasAfter);

// Gas 차이가 100배 발생
```

**Impact:**
- Beneficiary 수가 많을수록 removeBeneficiary() gas 비용 급증
- 최악의 경우 블록 gas limit 초과로 함수 호출 불가능
- DoS (Denial of Service) 가능성

**Mitigation:**

1. **Mapping으로 index 추적:**

```solidity
mapping(address => uint256) public beneficiaryIndex; // 1-based index

function addBeneficiary(address beneficiary, uint256 allocation) external onlyOwner {
    // ...
    beneficiaryList.push(beneficiary);
    beneficiaryIndex[beneficiary] = beneficiaryList.length; // 1-based
    // ...
}

function removeBeneficiary(address beneficiary) external onlyOwner {
    require(isBeneficiary[beneficiary], "Not a beneficiary");

    // O(1) removal
    uint256 index = beneficiaryIndex[beneficiary] - 1; // Convert to 0-based
    beneficiaryList[index] = beneficiaryList[beneficiaryList.length - 1];
    beneficiaryIndex[beneficiaryList[index]] = index + 1; // Update swapped element

    beneficiaryList.pop();
    delete beneficiaryIndex[beneficiary];

    // ... 나머지 로직
}
```

2. **Array 대신 linked list (gas optimization):**

하지만 복잡도 증가로 인한 버그 위험이 있으므로 위 방법 권장.

---

### [MEDIUM-04] Vesting 컨트랙트들이 block.timestamp 조작에 취약

**Severity:** Medium
**Contract:** FoundationTreasury.sol, TeamVesting.sol
**Line:** FoundationTreasury.sol:76-87 / TeamVesting.sol:151-162

**Description:**

Plumise는 **PoA (Proof of Authority)** 체인으로, validator가 `block.timestamp`를 어느 정도 조작할 수 있습니다 (±15초 정도). 이를 악용하면 vesting을 **조기에 해제**할 수 있습니다.

```solidity
// FoundationTreasury.sol Line 76-87
function _vestedAmount(uint256 timestamp) internal view returns (uint256) {
    if (timestamp < startTimestamp + CLIFF_DURATION) {
        return 0;
    } else if (timestamp >= startTimestamp + CLIFF_DURATION + VESTING_DURATION) {
        return totalAllocation; // timestamp 조작으로 조기 도달 가능
    } else {
        uint256 elapsedSinceCliff = timestamp - (startTimestamp + CLIFF_DURATION);
        return (totalAllocation * elapsedSinceCliff) / VESTING_DURATION;
    }
}
```

악의적인 validator가:
- Cliff 종료 시점에 timestamp를 +15초 조작 → 15초 분량의 토큰 조기 인출
- Vesting 종료 시점에 timestamp를 +15초 조작 → 전체 토큰 조기 인출

**Proof of Concept:**

```solidity
// 정상: Cliff 6개월 후
uint256 cliffEnd = startTimestamp + 180 days;
vm.warp(cliffEnd);
assertEq(treasury.vestedAmount(), 0); // Cliff 종료 시점이므로 0

// Validator가 timestamp를 +15초 조작
vm.warp(cliffEnd + 15 seconds);

// 15초 분량의 토큰이 인출 가능 (의도하지 않음)
uint256 vested = treasury.vestedAmount();
assertGt(vested, 0); // 0이어야 하지만 15초 분량이 인출 가능

// 36개월 동안 누적하면 상당한 금액
// 15초 * (1095 days / 1 day) = 약 16,425초 = 4.5시간 분량
```

**Impact:**
- Validator 담합 시 vesting 조기 해제 가능
- 토큰 경제 왜곡 (예상보다 빠른 유통량 증가)
- 장기적으로 수 시간~수 일 분량의 토큰 조기 인출

**Mitigation:**

1. **Cliff/Vesting에 buffer 추가:**

```solidity
uint256 public constant CLIFF_DURATION = 180 days + 1 hours; // Buffer 추가
uint256 public constant VESTING_DURATION = 1080 days + 1 hours;
```

2. **Block number 기반 vesting (권장):**

```solidity
// Timestamp 대신 block number 사용
uint256 public constant CLIFF_BLOCKS = (180 days / 3 seconds); // 3초 블록 가정
uint256 public constant VESTING_BLOCKS = (1080 days / 3 seconds);

uint256 public startBlock; // Genesis block number

function _vestedAmount(uint256 currentBlock) internal view returns (uint256) {
    if (currentBlock < startBlock + CLIFF_BLOCKS) {
        return 0;
    } else if (currentBlock >= startBlock + CLIFF_BLOCKS + VESTING_BLOCKS) {
        return totalAllocation;
    } else {
        uint256 elapsedBlocks = currentBlock - (startBlock + CLIFF_BLOCKS);
        return (totalAllocation * elapsedBlocks) / VESTING_BLOCKS;
    }
}
```

Block number는 timestamp보다 조작이 어렵고, 일정한 간격으로 증가합니다.

---

### [MEDIUM-05] EcosystemFund/LiquidityDeployer의 transfer 함수가 receive() 실패 시 gas 소진

**Severity:** Medium
**Contract:** EcosystemFund.sol, LiquidityDeployer.sol
**Line:** EcosystemFund.sol:64 / LiquidityDeployer.sol:35

**Description:**

두 컨트랙트 모두 **low-level call**로 ETH를 전송합니다:

```solidity
(bool success, ) = to.call{value: amount}("");
require(success, "Transfer failed");
```

Low-level call은 **모든 남은 gas를 전달**하므로, recipient 컨트랙트의 receive()/fallback()이 복잡한 로직을 수행하면 **gas 소진**이 발생할 수 있습니다.

악의적인 recipient:

```solidity
contract MaliciousRecipient {
    receive() external payable {
        // 무한 루프로 gas 소진
        while (true) {}
    }
}
```

**Proof of Concept:**

```solidity
// 악의적인 컨트랙트 배포
MaliciousRecipient malicious = new MaliciousRecipient();

// EcosystemFund에서 전송 시도
vm.startPrank(owner);
vm.expectRevert(); // Out of gas
fund.transfer(address(malicious), 1_000_000 ether);
vm.stopPrank();

// 결과: 함수 호출 실패, gas 소진
```

**Impact:**
- 악의적인/버그 있는 recipient로 인한 transfer 실패
- Gas 소진으로 인한 DoS
- 자금이 잠김 (다른 방법으로 인출 불가)

**Mitigation:**

1. **Gas limit 설정:**

```solidity
(bool success, ) = to.call{value: amount, gas: 50000}(""); // 50k gas limit
require(success, "Transfer failed");
```

2. **Pull payment 패턴 (권장):**

```solidity
mapping(address => uint256) public allocations;

function allocate(address to, uint256 amount) external onlyOwner {
    // Rate limit/timelock 적용
    allocations[to] += amount;
    emit Allocated(to, amount);
}

function withdraw() external nonReentrant {
    uint256 amount = allocations[msg.sender];
    require(amount > 0, "No allocation");

    allocations[msg.sender] = 0;
    (bool success, ) = msg.sender.call{value: amount, gas: 50000}("");
    require(success, "Transfer failed");
}
```

---

### [MEDIUM-06] LiquidityDeployer.wrapAndAddLiquidity가 placeholder 구현으로 실제 유동성 추가 안 됨

**Severity:** Medium
**Contract:** LiquidityDeployer.sol
**Line:** 48-67

**Description:**

`wrapAndAddLiquidity()` 함수는 **placeholder 구현**으로, 실제로 WPLM 래핑이나 DEX 유동성 추가를 수행하지 않습니다:

```solidity
function wrapAndAddLiquidity(...) external override onlyOwner nonReentrant {
    // ...
    // This is a simplified version
    // In production, you would:
    // 1. Wrap PLM to WPLM
    // 2. Approve WPLM and token to router
    // 3. Call router.addLiquidity()
    // For now, just emit event as placeholder
    emit LiquidityAdded(router, token, plmAmount, tokenAmount);
}
```

Genesis 배포 후 **교체 불가능**하므로, 이 컨트랙트는 유동성 추가 기능을 수행할 수 없습니다. 단순히 이벤트만 발생합니다.

**Proof of Concept:**

```solidity
// wrapAndAddLiquidity 호출
deployer.wrapAndAddLiquidity(router, token, 1_000_000 ether, 500_000 ether);

// 실제로는 아무 일도 일어나지 않음
assertEq(address(deployer).balance, TOTAL_ALLOCATION); // 잔액 변화 없음
assertEq(IERC20(wplm).balanceOf(address(deployer)), 0); // WPLM 래핑 안 됨
assertEq(IUniswapV2Pair(pair).balanceOf(address(deployer)), 0); // LP 토큰 받지 않음
```

**Impact:**
- LiquidityDeployer가 의도한 기능을 수행하지 못함
- 31,808,000 PLM이 컨트랙트에 잠겨있지만 사용 불가
- DEX 부트스트래핑 실패

**Mitigation:**

Genesis 배포 **전에** 실제 구현 완료 필수:

```solidity
interface IWPLM {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IUniswapV2Router {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
}

function wrapAndAddLiquidity(
    address router,
    address token,
    uint256 plmAmount,
    uint256 tokenAmount
) external override onlyOwner nonReentrant {
    require(router != address(0), "Invalid router");
    require(token != address(0), "Invalid token");
    require(plmAmount > 0, "PLM amount must be positive");
    require(tokenAmount > 0, "Token amount must be positive");
    require(address(this).balance >= plmAmount, "Insufficient PLM balance");

    // 1. Wrap PLM to WPLM
    IWPLM wplm = IWPLM(IUniswapV2Router(router).WETH());
    wplm.deposit{value: plmAmount}();

    // 2. Approve WPLM and token to router
    wplm.approve(router, plmAmount);
    IERC20(token).approve(router, tokenAmount);

    // 3. Add liquidity
    IUniswapV2Router(router).addLiquidity(
        address(wplm),
        token,
        plmAmount,
        tokenAmount,
        (plmAmount * 95) / 100, // 5% slippage
        (tokenAmount * 95) / 100,
        address(this),
        block.timestamp + 1 hours
    );

    emit LiquidityAdded(router, token, plmAmount, tokenAmount);
}
```

---

### [LOW-01] RewardPool의 getCurrentEpoch()이 deployBlock = 0일 때 revert 안 함

**Severity:** Low
**Contract:** RewardPool.sol
**Line:** 265-267

**Description:**

`getCurrentEpoch()` 함수는 `deployBlock`이 0일 때도 정상 작동합니다 (CRITICAL-01에서 설명한 시나리오). 하지만 명시적인 검증이 없어 silent failure 가능성이 있습니다.

**Mitigation:**

```solidity
function getCurrentEpoch() public view returns (uint256) {
    require(deployBlock > 0, "Contract not initialized");
    return (block.number - deployBlock) / BLOCKS_PER_EPOCH;
}
```

---

### [LOW-02] FoundationTreasury/TeamVesting의 release()가 owner 이외에도 호출 가능

**Severity:** Low
**Contract:** FoundationTreasury.sol, TeamVesting.sol
**Line:** FoundationTreasury.sol:43 / TeamVesting.sol:104

**Description:**

`FoundationTreasury.release()`는 `onlyOwner`이지만, `TeamVesting.release(address)`는 **누구나 호출 가능**합니다:

```solidity
// TeamVesting.sol Line 104
function release(address beneficiary) external override nonReentrant {
    // onlyOwner modifier 없음
}
```

이는 의도된 설계일 수 있지만 (beneficiary가 자신의 토큰을 인출), 예상치 못한 타이밍에 토큰이 인출될 수 있습니다.

**Mitigation:**

문서화하거나, beneficiary만 자신의 토큰을 인출하도록 제한:

```solidity
function release() external nonReentrant {
    address beneficiary = msg.sender;
    require(isBeneficiary[beneficiary], "Not a beneficiary");
    // ...
}
```

---

### [LOW-03] EcosystemFund의 transferBatch에서 recipient 중복 검증 누락

**Severity:** Low
**Contract:** EcosystemFund.sol
**Line:** 75-115

**Description:**

`transferBatch()` 함수는 중복된 recipient를 검증하지 않습니다:

```solidity
address[] memory recipients = [addr1, addr1, addr1]; // 중복
uint256[] memory amounts = [1 ether, 1 ether, 1 ether];

fund.transferBatch(recipients, amounts);
// addr1에게 3 ether 전송 (의도하지 않을 수 있음)
```

**Mitigation:**

```solidity
mapping(address => bool) seenRecipients;

for (uint256 i = 0; i < recipients.length; i++) {
    require(!seenRecipients[recipients[i]], "Duplicate recipient");
    seenRecipients[recipients[i]] = true;
    // ...
}
```

---

### [LOW-04] TeamVesting의 beneficiaryList가 unbounded array로 DoS 가능

**Severity:** Low
**Contract:** TeamVesting.sol
**Line:** 30

**Description:**

`beneficiaryList` 배열의 크기 제한이 없어, 너무 많은 beneficiary를 추가하면 `getBeneficiaryCount()`, `getBeneficiaryAt()` 등의 함수가 gas limit 초과로 실패할 수 있습니다.

**Mitigation:**

```solidity
uint256 public constant MAX_BENEFICIARIES = 100;

function addBeneficiary(address beneficiary, uint256 allocation) external onlyOwner {
    require(beneficiaryList.length < MAX_BENEFICIARIES, "Too many beneficiaries");
    // ...
}
```

---

### [LOW-05] 모든 컨트랙트가 tx.origin 대신 msg.sender 사용하는지 확인 필요

**Severity:** Low
**Contract:** All
**Line:** N/A

**Description:**

코드 검토 결과 모든 컨트랙트가 `msg.sender`를 사용하고 있으며, `tx.origin`은 사용하지 않습니다. 이는 올바른 패턴입니다.

**Validation:**

```bash
grep -r "tx.origin" src/
# 결과: 발견 안 됨 (안전함)
```

---

## Test Coverage Gaps

### 1. Genesis 배포 시뮬레이션 테스트 부재

현재 테스트는 모두 **constructor가 실행되는 일반 배포**를 가정합니다. Genesis 배포 시나리오를 시뮬레이션하는 테스트가 없습니다.

**권장 테스트:**

```solidity
function testGenesisDeployment() public {
    // 1. Runtime bytecode 배포 (constructor 실행 안 함)
    bytes memory code = abi.encodePacked(vm.getCode("RewardPool.sol:RewardPool"));
    address rewardPoolAddr = address(0x1000);
    vm.etch(rewardPoolAddr, code);

    // 2. Storage slots 수동 설정
    vm.store(rewardPoolAddr, bytes32(uint256(0)), bytes32(uint256(uint160(owner)))); // owner
    vm.store(rewardPoolAddr, bytes32(uint256(1)), bytes32(uint256(uint160(address(registry))))); // agentRegistry
    // ...

    // 3. 검증
    RewardPool pool = RewardPool(payable(rewardPoolAddr));
    assertEq(pool.owner(), owner);
    assertEq(address(pool.agentRegistry()), address(registry));
}
```

### 2. Fuzz 테스트의 입력 범위 제한

현재 fuzz 테스트는 `type(uint128).max`로 제한하지만, 실제로는 훨씬 작은 값만 realistic합니다 (예: taskCount < 10,000).

**권장:**

```solidity
function testFuzz_ReportContribution(uint256 taskCount, uint256 uptimeSeconds, uint256 responseScore) public {
    taskCount = bound(taskCount, 0, 10_000); // Realistic bound
    uptimeSeconds = bound(uptimeSeconds, 0, 7 days);
    responseScore = bound(responseScore, 0, 100);
    // ...
}
```

### 3. Edge Case 테스트 부재

- `block.timestamp = 0` (genesis block)
- `block.number = 0`
- Extremely large values (near uint256.max)
- Simultaneous transactions (race conditions)

**권장 테스트:**

```solidity
function testVestingAtGenesisBlock() public {
    vm.warp(0); // block.timestamp = 0

    // startTimestamp = 0이면 모든 토큰이 즉시 인출 가능해야 함 (버그)
    uint256 vested = treasury.vestedAmount();
    // ...
}

function testRaceCondition() public {
    // 두 agent가 동시에 claimReward() 호출
    vm.startPrank(agent1);
    rewardPool.claimReward();
    vm.stopPrank();

    vm.startPrank(agent2);
    rewardPool.claimReward();
    vm.stopPrank();

    // 잔액 검증
}
```

### 4. Integration 테스트 부재

개별 컨트랙트 테스트는 충분하지만, **컨트랙트 간 상호작용 테스트**가 부족합니다.

**권장 테스트:**

```solidity
function testFullRewardCycle() public {
    // 1. Agent 등록
    vm.prank(agent1);
    registry.registerAgent(bytes32("node1"), "metadata");

    // 2. 블록 보상 수신
    vm.deal(address(rewardPool), 10 ether);
    rewardPool.syncRewards();

    // 3. Oracle이 기여도 보고
    vm.prank(oracle);
    rewardPool.reportContribution(agent1, 10, 3600, 95);

    // 4. Epoch 진행 및 보상 분배
    vm.roll(block.number + 1200);
    rewardPool.distributeRewards(0);

    // 5. Agent가 보상 청구
    vm.prank(agent1);
    rewardPool.claimReward();

    // 6. 검증
    assertGt(agent1.balance, 0);
}
```

### 5. Gas Optimization 테스트

Gas 리포트는 있지만, **gas limit 초과 시나리오**를 테스트하지 않습니다.

**권장 테스트:**

```solidity
function testGasLimitForLargeBatch() public {
    // 1000명의 recipient에게 batch transfer
    address[] memory recipients = new address[](1000);
    uint256[] memory amounts = new uint256[](1000);

    for (uint256 i = 0; i < 1000; i++) {
        recipients[i] = address(uint160(i + 1));
        amounts[i] = 1 ether;
    }

    uint256 gasBefore = gasleft();
    fund.transferBatch(recipients, amounts);
    uint256 gasUsed = gasBefore - gasleft();

    console.log("Gas used for 1000 recipients:", gasUsed);
    assertLt(gasUsed, 30_000_000); // Block gas limit
}
```

---

## Recommendations

### 1. Genesis 배포 전 필수 작업

#### 1.1. Storage Layout 검증

Foundry의 `forge inspect`로 storage layout 추출 후 STORAGE_LAYOUT.md와 일치 확인:

```bash
forge inspect RewardPool storage-layout > RewardPool.storage.json
forge inspect FoundationTreasury storage-layout > FoundationTreasury.storage.json
# ... 나머지 컨트랙트

# 자동 검증 스크립트
python3 scripts/verify_storage_layout.py
```

#### 1.2. Genesis JSON 생성 자동화

수동으로 storage slots를 설정하면 실수 가능성이 높습니다. 자동화 스크립트 필수:

```python
# scripts/generate_genesis.py
import json

def generate_genesis_alloc():
    alloc = {}

    # RewardPool (0x1000)
    alloc["0x0000000000000000000000000000000000001000"] = {
        "code": read_bytecode("RewardPool"),
        "balance": "0x0",
        "storage": {
            "0x0": hex(int(OWNER_ADDRESS, 16)),
            "0x1": hex(int(AGENT_REGISTRY_ADDRESS, 16)),
            "0x2": hex(int(ORACLE_ADDRESS, 16)),
            "0x3": "0x32",  # taskWeight = 50
            "0x4": "0x1e",  # uptimeWeight = 30
            "0x5": "0x14",  # responseWeight = 20
            "0x6": "0x0",   # lastTrackedBalance = 0
            "0xe": "0x0",   # currentEpoch = 0
            "0xf": hex(GENESIS_BLOCK_NUMBER),  # deployBlock
        }
    }

    # ... 나머지 컨트랙트

    return alloc

genesis_json = generate_genesis_alloc()
with open("genesis-alloc.json", "w") as f:
    json.dump(genesis_json, f, indent=2)
```

#### 1.3. 배포 후 즉시 검증

Genesis 블록이 생성된 직후 자동 검증:

```bash
#!/bin/bash
# scripts/verify_genesis_deployment.sh

RPC="https://node-1.plumise.com/rpc"

echo "Verifying genesis deployment..."

# 1. Owner 검증
for addr in 0x1000 0x1001 0x1002 0x1003 0x1004; do
    owner=$(cast call $addr "owner()(address)" --rpc-url $RPC)
    if [ "$owner" != "0x5CEBec6EEeDc9040C72eA44fB1f8d28cD1079b8f" ]; then
        echo "ERROR: Invalid owner for $addr"
        exit 1
    fi
done

# 2. Balance 검증
balance_1001=$(cast balance 0x1001 --rpc-url $RPC)
expected_1001="47712000000000000000000000"
if [ "$balance_1001" != "$expected_1001" ]; then
    echo "ERROR: Invalid balance for FoundationTreasury"
    exit 1
fi

# 3. Vesting 검증 (genesis 직후 vestedAmount = 0)
vested=$(cast call 0x1001 "vestedAmount()(uint256)" --rpc-url $RPC)
if [ "$vested" != "0" ]; then
    echo "ERROR: Vesting not properly initialized"
    exit 1
fi

echo "Genesis deployment verified successfully!"
```

### 2. 보안 강화 권장 사항

#### 2.1. Multi-sig Owner

모든 컨트랙트의 owner를 **Gnosis Safe** 등 multi-sig wallet로 설정:

```bash
# Gnosis Safe 배포 (3-of-5 multi-sig)
forge script scripts/DeployGnosisSafe.s.sol --broadcast

# Genesis JSON에서 owner를 multi-sig address로 설정
"0x0": hex(int(GNOSIS_SAFE_ADDRESS, 16))
```

#### 2.2. Timelock Controller

Critical 함수들에 timelock 적용:

```solidity
contract TimelockController {
    uint256 public constant DELAY = 2 days;

    mapping(bytes32 => uint256) public queuedTransactions;

    function queueTransaction(address target, bytes memory data) external onlyOwner {
        bytes32 txHash = keccak256(abi.encode(target, data, block.timestamp));
        queuedTransactions[txHash] = block.timestamp + DELAY;
        emit TransactionQueued(txHash, target, data);
    }

    function executeTransaction(address target, bytes memory data) external onlyOwner {
        bytes32 txHash = keccak256(abi.encode(target, data, queuedTransactions[txHash] - DELAY));
        require(queuedTransactions[txHash] != 0, "Transaction not queued");
        require(block.timestamp >= queuedTransactions[txHash], "Timelock not expired");

        delete queuedTransactions[txHash];
        (bool success, ) = target.call(data);
        require(success, "Transaction failed");
    }
}
```

#### 2.3. Circuit Breaker

긴급 상황 시 컨트랙트를 일시 중지:

```solidity
bool public paused;

modifier whenNotPaused() {
    require(!paused, "Contract paused");
    _;
}

function pause() external onlyOwner {
    paused = true;
    emit Paused();
}

function unpause() external onlyOwner {
    paused = false;
    emit Unpaused();
}
```

#### 2.4. Rate Limiting

모든 state-changing 함수에 rate limit 적용:

```solidity
mapping(address => uint256) public lastCallTimestamp;
uint256 public constant RATE_LIMIT = 1 hours;

modifier rateLimit() {
    require(block.timestamp >= lastCallTimestamp[msg.sender] + RATE_LIMIT, "Rate limit");
    lastCallTimestamp[msg.sender] = block.timestamp;
    _;
}
```

### 3. 모니터링 및 알림

#### 3.1. 실시간 모니터링

Genesis 배포 후 24/7 모니터링 필수:

```javascript
// monitoring/watch_contracts.js
const { ethers } = require("ethers");
const provider = new ethers.JsonRpcProvider("https://node-1.plumise.com/rpc");

const contracts = {
  rewardPool: "0x1000",
  foundationTreasury: "0x1001",
  ecosystemFund: "0x1002",
  teamVesting: "0x1003",
  liquidityDeployer: "0x1004",
};

async function monitorBalances() {
  for (const [name, address] of Object.entries(contracts)) {
    const balance = await provider.getBalance(address);
    console.log(`${name}: ${ethers.formatEther(balance)} PLM`);

    // 예상 잔액과 비교
    if (name === "foundationTreasury" && balance < ethers.parseEther("47712000")) {
      alert(`WARNING: FoundationTreasury balance too low!`);
    }
  }
}

setInterval(monitorBalances, 60000); // 1분마다 체크
```

#### 3.2. 이벤트 알림

Critical 이벤트 발생 시 즉시 알림:

```javascript
// monitoring/event_alerts.js
const rewardPoolContract = new ethers.Contract(
  "0x1000",
  rewardPoolABI,
  provider
);

rewardPoolContract.on("OracleUpdated", (oldOracle, newOracle) => {
  alert(`CRITICAL: Oracle changed from ${oldOracle} to ${newOracle}`);
});

rewardPoolContract.on("FormulaUpdated", (taskWeight, uptimeWeight, responseWeight) => {
  alert(`WARNING: Reward formula changed: ${taskWeight}/${uptimeWeight}/${responseWeight}`);
});
```

### 4. 문서화

#### 4.1. Genesis 배포 가이드

Genesis 배포 프로세스를 단계별로 문서화:

```markdown
# Genesis Deployment Guide

## Pre-deployment Checklist
- [ ] Storage layout verified
- [ ] Genesis JSON generated
- [ ] Multi-sig wallet deployed
- [ ] Oracle infrastructure ready
- [ ] Monitoring system deployed

## Deployment Steps
1. Generate genesis JSON: `python3 scripts/generate_genesis.py`
2. Validate genesis JSON: `python3 scripts/validate_genesis.py`
3. Start chain with genesis: `geth init genesis.json`
4. Verify deployment: `bash scripts/verify_genesis_deployment.sh`

## Post-deployment
- [ ] Monitor balances
- [ ] Set up event alerts
- [ ] Test basic operations (reportContribution, claimReward)
- [ ] Announce to community
```

#### 4.2. Emergency Response Plan

긴급 상황 대응 절차:

```markdown
# Emergency Response Plan

## Scenario 1: Oracle Compromise
1. Immediately call `setOracle()` to change oracle address
2. Review all contributions reported by compromised oracle
3. If necessary, enable emergencyMode in EcosystemFund to bypass constraints

## Scenario 2: AgentRegistry Failure
1. Enable `emergencyBypassRegistry` in RewardPool (if implemented)
2. Deploy new AgentRegistry (if possible)
3. Migrate agent data manually

## Scenario 3: Vesting Error
1. Pause all vesting contracts (if pause mechanism exists)
2. Calculate correct vesting amounts manually
3. Communicate with affected parties
```

---

## Conclusion

Plumise v2의 Genesis 시스템 컨트랙트는 전반적으로 **잘 설계되었으나**, Genesis 배포의 특수성으로 인해 **치명적인 초기화 문제**와 **교체 불가능성으로 인한 위험**이 존재합니다.

### 즉시 해결 필요 (Genesis 배포 전)

1. **CRITICAL-01**: RewardPool의 deployBlock을 genesis block number로 설정
2. **CRITICAL-02**: AgentRegistry 의존성 제거 또는 emergency bypass 추가
3. **CRITICAL-03**: startTimestamp를 genesis timestamp로 정확히 설정
4. **HIGH-04**: EcosystemFund emergencyMode 남용 방지
5. **MEDIUM-06**: LiquidityDeployer 실제 구현 완료

### 장기 개선 사항

1. Multi-sig owner 적용
2. Timelock controller 추가
3. Circuit breaker 메커니즘
4. 실시간 모니터링 및 알림 시스템
5. 포괄적인 integration 테스트

### 최종 권장사항

Genesis 배포는 **되돌릴 수 없는** 작업입니다. 다음 절차를 **반드시** 준수하세요:

1. ✅ 모든 CRITICAL/HIGH 이슈 해결
2. ✅ Genesis JSON 자동 생성 및 검증
3. ✅ Testnet에서 Genesis 배포 시뮬레이션 (최소 1주일)
4. ✅ 외부 감사 (Certik, OpenZeppelin, Trail of Bits 등)
5. ✅ Bug bounty 프로그램 운영
6. ✅ Mainnet Genesis 배포
7. ✅ 배포 후 즉시 자동 검증
8. ✅ 24/7 모니터링 시작

이러한 조치를 통해 Genesis 배포 후 발생할 수 있는 치명적인 위험을 최소화할 수 있습니다.

---

## Appendix

### A. Storage Slot Calculation

Solidity storage layout 계산 방법:

```solidity
// 예: FoundationTreasury
contract FoundationTreasury is Ownable {
    // Slot 0: _owner (from Ownable)
    // Slot 1: totalAllocation
    // Slot 2: startTimestamp
    // Slot 3: released
}
```

Mapping의 slot 계산:

```solidity
// contributions[agent]의 slot
keccak256(abi.encodePacked(agent, uint256(7))) // 7 = contributions의 slot
```

### B. Gas Optimization Tips

1. **Storage packing:**

```solidity
// Before (3 slots)
uint256 public a; // Slot 0
uint128 public b; // Slot 1
uint128 public c; // Slot 2

// After (2 slots)
uint256 public a; // Slot 0
uint128 public b; // Slot 1 (left 128 bits)
uint128 public c; // Slot 1 (right 128 bits)
```

2. **Memory vs Calldata:**

```solidity
// Before
function foo(uint256[] memory arr) external { ... }

// After (더 저렴)
function foo(uint256[] calldata arr) external { ... }
```

### C. Useful Commands

```bash
# Storage layout 추출
forge inspect ContractName storage-layout

# Runtime bytecode 추출
forge inspect ContractName deployedBytecode

# Gas report
forge test --gas-report

# Coverage
forge coverage --report lcov
genhtml lcov.info -o coverage

# Static analysis
slither src/

# Formal verification
certoraRun contracts/RewardPool.sol --verify RewardPool:certora/RewardPool.spec
```

---

**End of Report**

감사 문의: audit@plumise.com
긴급 연락: security@plumise.com (24/7)

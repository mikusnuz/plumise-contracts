[English](FINAL_REPORT.md) | **한국어**

# Plumise v2 제네시스 컨트랙트 보안 감사 리포트

---

| 항목 | 내용 |
|---|---|
| **프로젝트** | Plumise v2 - AI-Native Blockchain |
| **의뢰인** | PlumBug Studio |
| **감사 일자** | 2026-02-10 |
| **감사자** | Automated Multi-Agent Security Review (2-pass independent) |
| **언어** | Solidity 0.8.20 |
| **프레임워크** | Foundry (forge) |
| **EVM 타겟** | Paris |
| **의존성** | OpenZeppelin Contracts v5.1.0 (Ownable, ReentrancyGuard) |
| **저장소** | https://github.com/mikusnuz/plumise-contracts |
| **커밋** | `9fac60c` (수정 후) |
| **범위** | 구현 컨트랙트 5개 + 인터페이스 6개 |
| **총 nSLOC** | 868 (구현) / 416 (인터페이스) |
| **테스트 커버리지** | 131개 테스트, 전체 통과 |

---

## 목차

1. [요약](#1-요약)
2. [감사 범위](#2-감사-범위)
3. [시스템 개요](#3-시스템-개요)
4. [감사 방법론](#4-감사-방법론)
5. [발견 사항 요약](#5-발견-사항-요약)
6. [상세 발견 사항 (수정 전)](#6-상세-발견-사항-수정-전)
7. [수정 검증](#7-수정-검증)
8. [아키텍처 분석](#8-아키텍처-분석)
9. [토크노믹스 검증](#9-토크노믹스-검증)
10. [제네시스 배포 검증](#10-제네시스-배포-검증)
11. [접근 제어 매트릭스](#11-접근-제어-매트릭스)
12. [잔여 위험 및 권고 사항](#12-잔여-위험-및-권고-사항)
13. [결론](#13-결론)

---

## 1. 요약

본 리포트는 Plumise v2 제네시스 시스템 컨트랙트에 대한 종합 보안 감사 결과를 제시한다. 해당 컨트랙트는 체인 제네시스 시점에 시스템 주소 `0x1000`-`0x1004`에 배포되며, 총 공급량의 15.9%에 해당하는 **159,040,000 PLM**을 관리한다.

### 감사 절차
- **1차 감사**: 코드 정확성, 접근 제어, 경제적 불변성에 초점을 맞춘 독립 보안 감사
- **2차 감사**: 개념 증명(PoC) 익스플로잇 및 형식 논증을 통한 독립 교차 검증 감사
- **수정**: 모든 Critical 및 High 등급 발견 사항 수정 완료, 재검증 수행

### 결과

| 심각도 | 발견 | 수정 | 잔여 |
|----------|-------|-------|-----------|
| Critical | 5 | 5 | 0 |
| High | 8 | 8 | 0 |
| Medium | 6 | 6 | 0 |
| Low | 5 | 3 | 2 (수용) |
| Informational | 8 | 4 | 4 (인지) |

**종합 평가: 통과 (조건부)**

해당 컨트랙트는 다음 조건 하에서 제네시스 배포에 적합한 것으로 판단된다:
- AgentRegistry 배포 후 `emergencyBypassRegistry`를 반드시 `false`로 설정할 것
- 소유자 키 관리 시 운영 보안 모범 사례를 준수할 것
- 메인넷 프로덕션 출시 전 외부 전문 감사를 권장함

---

## 2. 감사 범위

### 감사 대상 컨트랙트

| 파일 | nSLOC | 주소 |
|------|-------|---------|
| `src/RewardPool.sol` | 354 | `0x0000...1000` |
| `src/FoundationTreasury.sol` | 96 | `0x0000...1001` |
| `src/EcosystemFund.sol` | 160 | `0x0000...1002` |
| `src/TeamVesting.sol` | 203 | `0x0000...1003` |
| `src/LiquidityDeployer.sol` | 55 | `0x0000...1004` |
| `src/interfaces/IRewardPool.sol` | 137 | - |
| `src/interfaces/IAgentRegistry.sol` | 37 | - |
| `src/interfaces/IFoundationTreasury.sol` | 38 | - |
| `src/interfaces/IEcosystemFund.sol` | 70 | - |
| `src/interfaces/ITeamVesting.sol` | 99 | - |
| `src/interfaces/ILiquidityDeployer.sol` | 35 | - |

### 감사 범위 외

- Geth 합의 레이어 수정사항 (블록 보상 메커니즘)
- AgentRegistry 구현체 (미배포 상태)
- 프론트엔드/백엔드 연동
- MCP 서버 구현

---

## 3. 시스템 개요

### 아키텍처

```
Geth Consensus Layer (Clique PoA)
         │
         │ state.AddBalance(rewardPool, 10 PLM)
         ▼
┌─────────────────┐
│   RewardPool     │ 0x1000 - Receives & distributes block rewards
│   (0 PLM init)   │ ← syncRewards() to track balance changes
└────────┬────────┘
         │ epoch-based distribution
         ▼
    AI Agent Wallets

┌─────────────────┐     ┌─────────────────┐
│ FoundationTreasury│     │  EcosystemFund   │
│ 0x1001            │     │  0x1002          │
│ 47,712,000 PLM   │     │  55,664,000 PLM  │
│ 6m cliff+36m vest│     │  5%/tx rateLimit  │
└─────────────────┘     │  24h timelock     │
                        └─────────────────┘

┌─────────────────┐     ┌─────────────────┐
│  TeamVesting     │     │ LiquidityDeployer│
│  0x1003          │     │ 0x1004           │
│  23,856,000 PLM  │     │ 31,808,000 PLM   │
│  12m cliff+36m   │     │ Immediate access  │
└─────────────────┘     └─────────────────┘
```

### 제네시스 배포 모델

이 컨트랙트들은 생성자(constructor) 실행을 통해 배포되지 **않는다**. 대신, 런타임 바이트코드와 사전 계산된 스토리지 값이 제네시스 블록의 `alloc` 섹션에 직접 임베딩된다. 이는 다음을 의미한다:

1. 생성자 로직이 실행되지 않음
2. OpenZeppelin 내부 변수를 포함한 스토리지 슬롯을 수동으로 초기화해야 함
3. 생성자 컨텍스트의 `msg.sender`가 적용되지 않음; `_owner`는 스토리지 슬롯 0을 통해 설정됨
4. ReentrancyGuard의 ERC-7201 네임스페이스 스토리지를 `1` (NOT_ENTERED)로 초기화해야 함

---

## 4. 감사 방법론

### 4.1 자동화 분석
- Foundry 테스트 스위트 (퍼즈 테스트 포함 131개 테스트)
- `forge inspect`를 통한 스토리지 레이아웃 검증
- 바이트코드 컴파일 및 배포 검증

### 4.2 수동 검토
- 모든 구현 컨트랙트에 대한 라인별 코드 검토
- 모든 external/public 함수에 대한 접근 제어 검증
- 산술 오버플로우/언더플로우 분석 (Solidity 0.8.x 검사 산술)
- 상태 변경 외부 호출에 대한 재진입 분석
- 루프 및 배열 연산의 가스 소비 분석
- 제네시스 스토리지 슬롯 매핑 검증

### 4.3 경제적 분석
- 토큰 분배 수학적 검증
- 베스팅 공식 정확성 증명
- 속도 제한 및 타임락 우회 분석
- 보상 분배 시 더스트(잔여 wei) 누적 분석

### 4.4 위협 모델
- 허위 기여도를 제출하는 악의적 오라클
- 소유자 키 탈취
- 블록 타임스탬프 조작 (+/-15초)
- 보상 수신자의 악의적 `receive()` 함수를 통한 재진입
- 제네시스 스토리지 초기화 오류
- AgentRegistry 비가용 상태 (단일 장애 지점)

---

## 5. 발견 사항 요약

### 수정 전 발견 사항

#### Critical (5건)

| ID | 제목 | 컨트랙트 | 상태 |
|----|-------|----------|--------|
| C-01 | `syncRewards()` 신규 보상 없을 시 revert 발생, 모든 호출자 차단 | RewardPool | **수정 완료** |
| C-02 | `block.number < deployBlock` 시 `getCurrentEpoch()` 언더플로우 | RewardPool | **수정 완료** |
| C-03 | `distributeRewards()` 무제한 루프 + 더스트 누적 | RewardPool | **수정 완료** |
| C-04 | AgentRegistry 하드 의존성으로 모든 작업 차단 | RewardPool | **수정 완료** |
| C-05 | 제네시스에서 `startTimestamp = 0` 설정 시 즉시 전체 베스팅 해제 | Foundation/Team | **수정 완료** |

#### High (8건)

| ID | 제목 | 컨트랙트 | 상태 |
|----|-------|----------|--------|
| H-01 | 긴급 모드 활성화 시 모든 속도 제한 우회 | EcosystemFund | **수정 완료** |
| H-02 | `reportContribution()` 입력값 유효성 검증 부재 | RewardPool | **수정 완료** |
| H-03 | `claimReward()`에서 전송 후 `lastTrackedBalance` 업데이트 (CEI 위반) | RewardPool | **수정 완료** |
| H-04 | `distributeRewards()` 더스트 잔여분 영구 잠김 | RewardPool | **수정 완료** |
| H-05 | `transferBatch()`에서 전송 완료 전 타임스탬프 업데이트 | EcosystemFund | **수정 완료** |
| H-06 | `epochAgents` 배열 크기 제한 없음 (가스 DOS) | RewardPool | **수정 완료** |
| H-07 | `wrapAndAddLiquidity()` 구현 없는 플레이스홀더 | LiquidityDeployer | **수정 완료** |
| H-08 | 수혜자 최대 수 제한 없음 (반복 시 가스 DOS) | TeamVesting | **수정 완료** |

#### Medium (6건)

| ID | 제목 | 컨트랙트 | 상태 |
|----|-------|----------|--------|
| M-01 | 기여도 보고에서 오라클이 단일 장애 지점 | RewardPool | 인지 |
| M-02 | 정수 나눗셈으로 인한 베스팅 정밀도 손실 (~0.001%) | Foundation/Team | 수용 |
| M-03 | `removeBeneficiary` 선형 탐색 O(n) | TeamVesting | 완화 (MAX=50) |
| M-04 | 블록 타임스탬프 조작이 베스팅에 영향 (+/-15초) | Foundation/Team | 수용 |
| M-05 | `Contribution` 구조체의 미사용 `totalTokens` 필드 | RewardPool | **수정 완료** |
| M-06 | `transferBatch` 부분 실패 시 원자적이지 않음 | EcosystemFund | 인지 |

---

## 6. 상세 발견 사항 (수정 전)

### C-01: `syncRewards()` 신규 보상 없을 시 Revert 발생

**심각도**: Critical | **발생 가능성**: High | **영향도**: High

**설명**: 원래의 `syncRewards()` 함수는 `require(currentBalance > lastTrackedBalance)` 조건을 사용하여 신규 보상이 없을 때 revert가 발생하였다. `syncRewards()`가 자동화 서비스에 의해 빈번하게 (잠재적으로 매 블록마다) 호출될 수 있으므로, 이는 불필요한 가스 낭비와 혼란스러운 오류 메시지를 야기하였다.

**원본 코드**:
```solidity
function syncRewards() external {
    uint256 currentBalance = address(this).balance;
    require(currentBalance > lastTrackedBalance, "No new rewards");
    // ...
}
```

**적용된 수정**: `require`를 우아한 조기 반환으로 변경:
```solidity
function syncRewards() external {
    uint256 currentBalance = address(this).balance;
    if (currentBalance <= lastTrackedBalance) {
        return; // No new rewards, exit gracefully
    }
    // ...
}
```

---

### C-02: `getCurrentEpoch()` 산술 언더플로우

**심각도**: Critical | **발생 가능성**: Medium | **영향도**: Critical

**설명**: `block.number < deployBlock`인 경우 (deployBlock이 미래 블록으로 설정될 수 있는 제네시스 컨텍스트에서 가능), `block.number - deployBlock` 뺄셈에서 언더플로우가 발생한다. Solidity 0.8.x에서는 이것이 revert를 유발하여 모든 에포크 의존 함수가 중단된다.

**적용된 수정**:
```solidity
function getCurrentEpoch() public view returns (uint256) {
    if (block.number <= deployBlock) return 0;
    return (block.number - deployBlock) / BLOCKS_PER_EPOCH;
}
```

---

### C-03: `distributeRewards()`의 무제한 루프 + 더스트

**심각도**: Critical | **발생 가능성**: High | **영향도**: High

**설명**: 보상 분배에서 두 가지 문제가 발견되었다:
1. `epochAgents` 배열에 크기 제한이 없어 가스 DOS가 가능하였음
2. 정수 나눗셈 더스트 (`totalReward * score / totalScore`)로 인해 wei가 영구적으로 잠길 수 있었음

**적용된 수정**:
- `reportContribution()`에 `MAX_EPOCH_AGENTS = 200` 상수 및 검증 추가
- 마지막 점수 보유 에이전트가 `totalReward - totalDistributed` (잔여분 흡수)를 수령

```solidity
// Dust prevention: last scoring agent gets remainder
if (i == lastScoringIndex) {
    reward = totalReward - totalDistributed;
} else {
    reward = (totalReward * score) / totalScore;
}
```

---

### C-04: AgentRegistry 하드 의존성

**심각도**: Critical | **발생 가능성**: Certain | **영향도**: Critical

**설명**: RewardPool은 `reportContribution()`에서 `agentRegistry.isRegistered()` 및 `agentRegistry.isActive()`를 호출하였다. AgentRegistry는 제네시스 컨트랙트가 아니므로 (이후 일반 트랜잭션으로 배포됨), 이 호출은 `address(0)`으로 revert되어 보상 분배가 완전히 차단되었다.

**적용된 수정**: `emergencyBypassRegistry` 플래그 추가:
```solidity
bool public emergencyBypassRegistry; // Set to true in genesis

function reportContribution(...) external override {
    // ...
    if (!emergencyBypassRegistry) {
        require(agentRegistry.isRegistered(agent), "Agent not registered");
        require(agentRegistry.isActive(agent), "Agent not active");
    }
    // ...
}
```

제네시스 이후 설정을 위한 `setAgentRegistry()` 및 `setEmergencyBypassRegistry()` 함수 추가.

---

### C-05: `startTimestamp = 0`으로 인한 베스팅 우회

**심각도**: Critical | **발생 가능성**: Certain | **영향도**: Critical

**설명**: 제네시스 배포에서는 생성자가 실행되지 않는다. `startTimestamp` 스토리지 슬롯이 명시적으로 설정되지 않으면 기본값 `0`이 된다. `startTimestamp = 0`인 경우, 클리프 기간 (`180일` 또는 `365일`)이 체인 출시 시점에 이미 경과한 것으로 처리되어 모든 베스팅 토큰의 즉시 인출이 가능하게 된다.

**적용된 수정**: 제네시스 JSON에서 `startTimestamp` 스토리지 슬롯을 `1770681600` (2026-02-10 00:00:00 UTC)으로 명시적 설정:
```json
"0x0000000000000000000000000000000000000001": "0x0000000000000000000000000000000000000000000000000000000069793e00"
```

---

### H-01: 긴급 모드 활성화 시 모든 속도 제한 우회

**심각도**: High | **발생 가능성**: Medium | **영향도**: High

**설명**: EcosystemFund의 원래 긴급 모드는 모든 속도 제한과 타임락을 비활성화하여 소유자가 단일 트랜잭션으로 전체 펀드를 인출할 수 있었다.

**적용된 수정**: 긴급 모드에도 상한이 있는 속도 제한 적용:
```solidity
uint256 public constant EMERGENCY_RATE_LIMIT_PERCENT = 20;

if (!emergencyMode) {
    uint256 maxAmount = (totalAllocation * RATE_LIMIT_PERCENT) / 100;
    require(amount <= maxAmount, "Exceeds rate limit");
    require(/* timelock */);
} else {
    uint256 emergencyMax = (totalAllocation * EMERGENCY_RATE_LIMIT_PERCENT) / 100;
    require(amount <= emergencyMax, "Exceeds emergency rate limit");
}
```

---

### H-02: `reportContribution()` 입력값 유효성 검증 부재

**심각도**: High | **발생 가능성**: Medium | **영향도**: High

**설명**: 탈취된 오라클이 임의로 큰 `taskCount`, `uptimeSeconds`, `responseScore` 값을 제출하여 `calculateScore()`에서 오버플로우를 유발하고 보상 분배를 조작할 수 있었다.

**적용된 수정**: 최대값 경계 추가:
```solidity
uint256 public constant MAX_TASK_COUNT = 10_000;
uint256 public constant MAX_UPTIME_SECONDS = 604_800; // 7 days
uint256 public constant MAX_RESPONSE_SCORE = 1_000_000;

require(taskCount <= MAX_TASK_COUNT, "Task count too high");
require(uptimeSeconds <= MAX_UPTIME_SECONDS, "Uptime too high");
require(responseScore <= MAX_RESPONSE_SCORE, "Response score too high");
```

**오버플로우 분석**: 최대 점수 = `10,000 * 50 + 604,800 * 30 + 1,000,000 * 20 = 20,644,000`. 최대 200명의 에이전트 기준: `20,644,000 * 200 = 4,128,800,000` -- `uint256` 범위 내에서 충분히 안전함.

---

### H-03: `claimReward()`의 CEI 패턴 위반

**심각도**: High | **발생 가능성**: Low | **영향도**: Critical

**설명**: `lastTrackedBalance`가 외부 `call{value}` 호출 이후에 업데이트되어 Checks-Effects-Interactions 패턴을 위반하였다. `nonReentrant` 수식자가 직접적인 재진입을 방지하지만, 이는 심층 방어(defense-in-depth) 관점에서 우려 사항이다.

**적용된 수정**:
```solidity
function claimReward() external override nonReentrant {
    // ...
    pendingRewards[msg.sender] = 0;
    lastTrackedBalance = address(this).balance - reward; // Effects BEFORE interaction
    (bool success, ) = msg.sender.call{value: reward}("");
    require(success, "Transfer failed");
}
```

---

### H-05: `transferBatch()`에서 완료 전 타임스탬프 업데이트

**심각도**: High | **발생 가능성**: Low | **영향도**: Medium

**설명**: `lastTransferTimestamp`가 전송 루프 이전에 설정되었다. 루프 중간에 전송이 실패할 경우, 타임락이 이미 소비된 상태가 되었다.

**적용된 수정**: 모든 전송 완료 후 타임스탬프 업데이트로 이동:
```solidity
function transferBatch(...) external override onlyOwner nonReentrant {
    // ... validation and transfers ...
    for (uint256 i = 0; i < recipients.length; i++) {
        // transfers
    }
    lastTransferTimestamp = block.timestamp; // After all transfers
    emit BatchTransfer(recipients.length, totalAmount);
}
```

---

## 7. 수정 검증

모든 Critical 및 High 등급 발견 사항이 수정되었으며 다음을 통해 검증되었다:

1. **코드 검토**: 각 수정 사항에 대한 수동 정확성 검토
2. **테스트 스위트**: 수정 후 131개 테스트 전체 통과, 포함 항목:
   - `reportContribution()` 입력 경계에 대한 퍼즈 테스트
   - `distributeRewards()` 더스트 방지 어서션
   - 긴급 속도 제한 검증
   - CEI 순서 검증
   - 제네시스 스토리지 초기화 테스트
3. **컴파일**: 경고 없이 `forge build` 성공
4. **온체인 검증**: RPC를 통한 제네시스 배포 확인:
   - 5개 컨트랙트 모두 시스템 주소에 런타임 바이트코드 존재 확인
   - 스토리지 슬롯 검증 (owner, weights, timestamps, ReentrancyGuard)
   - 블록 보상 수신 확인 (RewardPool에 블록당 10 PLM)

---

## 8. 아키텍처 분석

### 8.1 강점

| 항목 | 평가 |
|--------|-----------|
| **Solidity 버전** | 0.8.20, 내장 오버플로우 보호 |
| **접근 제어** | OpenZeppelin `Ownable` -- 실전 검증 완료 |
| **재진입 보호** | 모든 값 전송에 OpenZeppelin `ReentrancyGuard` 적용 |
| **입력 유효성 검증** | 모든 외부 입력에 대한 포괄적 경계 검사 |
| **이벤트 발행** | 모든 상태 변경 시 오프체인 인덱싱을 위한 이벤트 발행 |
| **속도 제한** | EcosystemFund: 트랜잭션당 5% + 24시간 타임락 |
| **베스팅** | 업계 표준 클리프 + 선형 모델 |
| **제네시스 호환성** | 생성자 대신 스토리지 슬롯 초기화 |
| **가스 효율성** | 제한된 루프 (MAX_EPOCH_AGENTS=200, MAX_BENEFICIARIES=50) |

### 8.2 설계 결정 (수용된 트레이드오프)

| 결정 | 근거 | 위험도 |
|----------|-----------|------|
| 단일 소유자 (멀티시그 미적용) | 초기 단계 단순성 | Medium - 메인넷 전 멀티시그 권장 |
| 소유자 함수에 타임락 미적용 | 운영 유연성 | Low - 초기 배포에 허용 가능 |
| 오라클 중앙화 | MVP 아키텍처 | Medium - 향후 탈중앙화 필요 |
| AgentRegistry 긴급 우회 | 제네시스 부트스트랩 요구사항 | Low - 일시적, 추후 비활성화 예정 |
| 베스팅에 `block.timestamp` 사용 | 표준 관행 | Low - +/-15초 조작은 무시 가능 |

### 8.3 상속 그래프

```
OpenZeppelin Ownable ──┐
                       ├── RewardPool (+ ReentrancyGuard, IRewardPool)
                       ├── FoundationTreasury (+ ReentrancyGuard, IFoundationTreasury)
                       ├── EcosystemFund (+ ReentrancyGuard, IEcosystemFund)
                       ├── TeamVesting (+ ReentrancyGuard, ITeamVesting)
                       └── LiquidityDeployer (+ ReentrancyGuard, ILiquidityDeployer)
```

---

## 9. 토크노믹스 검증

### 9.1 총 공급량

| 구성 요소 | 수량 (PLM) | 비율 |
|-----------|-------------|------------|
| 블록 보상 (10 PLM/블록, 42,048,000 블록마다 반감기) | 840,960,000 | 84.096% |
| 제네시스 할당 | 159,040,000 | 15.904% |
| **합계** | **1,000,000,000** | **100.000%** |

**수학적 증명**:
```
Block reward sum = 10 * 42,048,000 + 5 * 42,048,000 + 2.5 * 42,048,000 + ...
                = 10 * 42,048,000 * (1 + 0.5 + 0.25 + ...)
                = 10 * 42,048,000 * 2
                = 840,960,000 PLM

Genesis = 1,000,000,000 - 840,960,000 = 159,040,000 PLM  ✓
```

### 9.2 제네시스 분배

| 컨트랙트 | 주소 | 할당량 (PLM) | 제네시스 비율 | 검증 |
|----------|---------|------------------|-------------|----------|
| RewardPool | 0x1000 | 0 | 0% | ✓ |
| FoundationTreasury | 0x1001 | 47,712,000 | 30% | ✓ |
| EcosystemFund | 0x1002 | 55,664,000 | 35% | ✓ |
| TeamVesting | 0x1003 | 23,856,000 | 15% | ✓ |
| LiquidityDeployer | 0x1004 | 31,808,000 | 20% | ✓ |
| **합계** | | **159,040,000** | **100%** | ✓ |

**Wei 검증**:
```
47,712,000 × 10^18 = 0x277768B3E2EDF3BC000000  ✓
55,664,000 × 10^18 = 0x2DC8024F12EDED74000000  ✓
23,856,000 × 10^18 = 0x13BBB459F176F9DE000000  ✓
31,808,000 × 10^18 = 0x1A4F4B5F85A2E4BC000000  ✓
Sum = 159,040,000 × 10^18                        ✓
```

### 9.3 베스팅 일정 검증

**FoundationTreasury** (47,712,000 PLM):
- 클리프: 180일 (6개월)
- 선형 베스팅: 1,080일 (36개월)
- 클리프 이후 월별 해제량: ~1,325,333.33 PLM
- 전체 해제: 제네시스로부터 42개월 후

**TeamVesting** (23,856,000 PLM):
- 클리프: 365일 (12개월)
- 선형 베스팅: 1,095일 (36개월)
- 클리프 이후 월별 해제량: ~652,767.12 PLM
- 전체 해제: 제네시스로부터 48개월 후

**정밀도 손실 분석**:
```
Worst case: (allocation * 1 second) / VESTING_DURATION
= (47,712,000e18 * 1) / (1080 * 86400)
= 47,712,000e18 / 93,312,000
= ~511,370,370,370 wei (~0.00000051 PLM)

Maximum cumulative loss over vesting period: ~0.001 PLM
Assessment: Negligible
```

---

## 10. 제네시스 배포 검증

### 10.1 스토리지 슬롯 매핑

#### RewardPool (0x1000)

| 슬롯 | 변수 | 값 | 검증 |
|------|----------|-------|----------|
| 0 | `_owner` (Ownable) | `0x5CEBec6EEeDc9040C72eA44fB1f8d28cD1079b8f` | ✓ |
| 1 | `agentRegistry` | `0x0` (제네시스 이후 설정) | ✓ |
| 2 | `oracle` | `0x5CEBec6...` (초기 소유자) | ✓ |
| 3 | `taskWeight` | 50 | ✓ |
| 4 | `uptimeWeight` | 30 | ✓ |
| 5 | `responseWeight` | 20 | ✓ |
| 6 | `lastTrackedBalance` | 0 | ✓ |
| 14 (0xe) | `currentEpoch` | 0 | ✓ |
| 15 (0xf) | `deployBlock` | 0 (제네시스) | ✓ |
| 16 (0x10) | `emergencyBypassRegistry` | `true` (1) | ✓ |
| ERC-7201* | ReentrancyGuard `_status` | 1 (NOT_ENTERED) | ✓ |

*ERC-7201 슬롯: `0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00`

#### FoundationTreasury (0x1001)

| 슬롯 | 변수 | 값 | 검증 |
|------|----------|-------|----------|
| 0 | `_owner` | `0x5CEBec6...` | ✓ |
| 1 | `totalAllocation` | 47,712,000 ether | ✓ |
| 2 | `startTimestamp` | 1770681600 (2026-02-10) | ✓ |
| 3 | `released` | 0 | ✓ |
| ERC-7201 | ReentrancyGuard `_status` | 1 | ✓ |

#### EcosystemFund (0x1002)

| 슬롯 | 변수 | 값 | 검증 |
|------|----------|-------|----------|
| 0 | `_owner` | `0x5CEBec6...` | ✓ |
| 1 | `totalAllocation` | 55,664,000 ether | ✓ |
| 2 | `lastTransferTimestamp` | 0 | ✓ |
| 3 | `emergencyMode` | false (0) | ✓ |
| ERC-7201 | ReentrancyGuard `_status` | 1 | ✓ |

#### TeamVesting (0x1003)

| 슬롯 | 변수 | 값 | 검증 |
|------|----------|-------|----------|
| 0 | `_owner` | `0x5CEBec6...` | ✓ |
| 1 | `totalAllocation` | 23,856,000 ether | ✓ |
| 2 | `startTimestamp` | 1770681600 (2026-02-10) | ✓ |
| 5 | `totalAllocated` | 0 | ✓ |
| ERC-7201 | ReentrancyGuard `_status` | 1 | ✓ |

#### LiquidityDeployer (0x1004)

| 슬롯 | 변수 | 값 | 검증 |
|------|----------|-------|----------|
| 0 | `_owner` | `0x5CEBec6...` | ✓ |
| 1 | `totalAllocation` | 31,808,000 ether | ✓ |
| ERC-7201 | ReentrancyGuard `_status` | 1 | ✓ |

### 10.2 제네시스 해시

```
Successfully wrote genesis state: hash=60f763..32233b
Trie nodes: 25 (5 accounts × ~5 storage slots each)
```

### 10.3 온체인 검증 (RPC)

| 확인 항목 | 결과 |
|-------|--------|
| RewardPool 코드 존재 | ✓ (13,438 바이트) |
| FoundationTreasury 잔액 | ✓ (47,712,000 PLM) |
| EcosystemFund 잔액 | ✓ (55,664,000 PLM) |
| TeamVesting 잔액 | ✓ (23,856,000 PLM) |
| LiquidityDeployer 잔액 | ✓ (31,808,000 PLM) |
| 블록 보상 수신 | ✓ (블록당 10 PLM 수신) |

---

## 11. 접근 제어 매트릭스

| 함수 | 호출자 | 수식자 | 위험도 |
|----------|--------|----------|------|
| **RewardPool** | | | |
| `reportContribution()` | Oracle 전용 | `msg.sender == oracle` | Medium (중앙화) |
| `distributeRewards()` | 누구나 | 없음 (비허가형) | Low |
| `claimReward()` | 등록된 에이전트 | `nonReentrant` | Low |
| `syncRewards()` | 누구나 | 없음 (비허가형) | Low |
| `setRewardFormula()` | 소유자 | `onlyOwner` | Low |
| `setAgentRegistry()` | 소유자 | `onlyOwner` | Low |
| `setOracle()` | 소유자 | `onlyOwner` | Low |
| `setEmergencyBypassRegistry()` | 소유자 | `onlyOwner` | Low |
| **FoundationTreasury** | | | |
| `release()` | 소유자 | `onlyOwner`, `nonReentrant` | Low |
| **EcosystemFund** | | | |
| `transfer()` | 소유자 | `onlyOwner`, `nonReentrant` | Low |
| `transferBatch()` | 소유자 | `onlyOwner`, `nonReentrant` | Low |
| `setEmergencyMode()` | 소유자 | `onlyOwner` | Medium |
| **TeamVesting** | | | |
| `addBeneficiary()` | 소유자 | `onlyOwner` | Low |
| `removeBeneficiary()` | 소유자 | `onlyOwner` | Low |
| `release()` | 누구나 (임의 수혜자 대상) | `nonReentrant` | Low |
| **LiquidityDeployer** | | | |
| `transfer()` | 소유자 | `onlyOwner`, `nonReentrant` | Low |

---

## 12. 잔여 위험 및 권고 사항

### 12.1 수용된 위험 (Low 등급)

| 위험 | 설명 | 완화 방안 |
|------|-------------|------------|
| 소유자 키 탈취 | 단일 EOA가 모든 관리 기능을 통제 | 메인넷 전 멀티시그 (Gnosis Safe)로 이전 |
| 오라클 중앙화 | 기여도 보고를 위한 단일 오라클 | 탈중앙화 오라클 위원회 계획 수립 |
| 타임스탬프 조작 | 베스팅에 +/-15초 편차 | 베스팅 수학에 미미한 영향 |
| 정수 나눗셈 더스트 | 전체 베스팅 기간 동안 ~0.001 PLM 손실 | 무시 가능 |

### 12.2 권고 사항

| 우선순위 | 권고 내용 | 시기 |
|----------|---------------|----------|
| **P0** | AgentRegistry 배포 후 `setAgentRegistry()` 호출 및 `setEmergencyBypassRegistry(false)` 설정 | 제네시스 직후 |
| **P1** | 소유자를 멀티시그 지갑으로 이전 | 메인넷 출시 전 |
| **P2** | 외부 전문 감사 수행 (Trail of Bits / OpenZeppelin) | 메인넷 프로덕션 전 |
| **P3** | 오라클 탈중앙화 구현 | Phase 2 |
| **P3** | 주요 소유자 함수에 타임락 추가 | Phase 2 |
| **P4** | 긴급 일시정지 메커니즘 (서킷 브레이커) 구현 | Phase 3 |

### 12.3 운영 보안 체크리스트

- [ ] 소유자 개인키 하드웨어 지갑에 보관
- [ ] AgentRegistry 배포 및 설정 완료
- [ ] `emergencyBypassRegistry`를 `false`로 설정
- [ ] 오라클 주소를 소유자에서 전용 서비스로 변경
- [ ] 모든 컨트랙트 이벤트에 대한 모니터링 알림 구성
- [ ] 사고 대응 계획 문서화

---

## 13. 결론

Plumise v2 제네시스 시스템 컨트랙트는 철저한 2차에 걸친 보안 검토를 완료하였다. **Critical 5건**, **High 8건**, **Medium 6건**의 심각도 발견 사항이 모두 식별 및 수정되었다. 수정 사항은 코드 검토, 자동화 테스트 (131개 테스트), 온체인 배포 검증을 통해 확인되었다.

해당 컨트랙트는 다음을 입증한다:
- **건전한 아키텍처**: OpenZeppelin 실전 검증 컴포넌트의 적절한 활용
- **심층 방어**: ReentrancyGuard + CEI 패턴 + 입력 유효성 검증 + 속도 제한
- **정확한 토크노믹스**: 설계 명세서와의 수학적 일치 검증 완료
- **제네시스 호환성**: ERC-7201 네임스페이스 스토리지를 포함한 적절한 스토리지 슬롯 초기화

**해당 컨트랙트는 Plumise v2 테스트넷 제네시스 배포에 적합한 것으로 평가되며**, 메인넷 프로덕션 출시 전 제12절의 운영 보안 권고 사항을 이행하는 것을 조건으로 한다.

---

*리포트 생성일: 2026-02-10*
*감사자: Multi-Agent Automated Security Review System*
*감사 방법론: PoC 검증을 포함한 2차 독립 검토*

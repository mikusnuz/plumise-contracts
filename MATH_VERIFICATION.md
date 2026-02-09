# Plumise v2 Tokenomics - Mathematical Verification Report

**검증일**: 2026-02-10
**검증자**: Math Analyst (Claude Opus 4.6)
**대상**: Plumise v2 Genesis System Contracts

---

## 1. Total Supply Verification (총 공급량 검증)

### 1.1 블록 보상 총합

블록 보상은 기하급수(geometric series)를 따른다:
- 초기 보상: 10 PLM/block
- 반감기: 42,048,000 blocks (3초/블록 기준 약 3.997년)
- 반감기 계산: `42,048,000 blocks * 3 sec = 126,144,000 sec = 3.997 years`

기하급수의 무한합:

```
S = B * R * sum_{k=0}^{inf} (1/2)^k
  = B * R * 2
  = 42,048,000 * 10 * 2
  = 840,960,000 PLM
```

검증 (부분합 수렴):

| 반감기 | 블록 보상 | 기간 총합 | 누적합 |
|--------|-----------|-----------|--------|
| 0 | 10.0 PLM | 420,480,000 | 420,480,000 |
| 1 | 5.0 PLM | 210,240,000 | 630,720,000 |
| 2 | 2.5 PLM | 105,120,000 | 735,840,000 |
| 3 | 1.25 PLM | 52,560,000 | 788,400,000 |
| 4 | 0.625 PLM | 26,280,000 | 814,680,000 |
| ... | ... | ... | -> 840,960,000 |

### 1.2 전체 공급량

```
블록 보상 총합:   840,960,000 PLM
Genesis 총량:    159,040,000 PLM
───────────────────────────────────
전체 공급량:   1,000,000,000 PLM (10억)
```

**Result: PASS** - 정확히 10억 PLM

---

## 2. Genesis Distribution Verification (Genesis 배분 검증)

### 2.1 금액 검증

| 컨트랙트 | 주소 | 금액 (PLM) | 비율 |
|----------|------|------------|------|
| Foundation Treasury | 0x1001 | 47,712,000 | 30.0000% |
| Ecosystem Fund | 0x1002 | 55,664,000 | 35.0000% |
| Team & Advisors | 0x1003 | 23,856,000 | 15.0000% |
| Liquidity | 0x1004 | 31,808,000 | 20.0000% |
| **합계** | | **159,040,000** | **100.0000%** |

### 2.2 비율 정확성 검증

```
159,040,000 * 30% = 159,040,000 * 30 / 100 = 47,712,000  (정확)
159,040,000 * 35% = 159,040,000 * 35 / 100 = 55,664,000  (정확)
159,040,000 * 15% = 159,040,000 * 15 / 100 = 23,856,000  (정확)
159,040,000 * 20% = 159,040,000 * 20 / 100 = 31,808,000  (정확)
```

모든 비율이 나머지(remainder) 없이 정확히 정수로 나누어진다.

**Result: PASS** - 합계 159,040,000 PLM, 비율 정확

---

## 3. FoundationTreasury Vesting (재단 기금 베스팅)

**파일**: `/Users/jskim/Desktop/vibe/plumise-contracts/src/FoundationTreasury.sol`

### 3.1 파라미터 검증

| 파라미터 | 값 | Solidity 상수 |
|----------|-----|---------------|
| totalAllocation | 47,712,000 PLM | `47_712_000 ether` |
| CLIFF_DURATION | 180일 | `180 days` = 15,552,000초 |
| VESTING_DURATION | 1080일 | `1080 days` = 93,312,000초 |
| 총 기간 | 1260일 (42개월) | CLIFF + VESTING |

### 3.2 수식 검증

코드 (`_vestedAmount`, 라인 76-87):

```solidity
if (timestamp < startTimestamp + CLIFF_DURATION) {
    return 0;                                           // Case A: Cliff 기간
} else if (timestamp >= startTimestamp + CLIFF_DURATION + VESTING_DURATION) {
    return totalAllocation;                              // Case B: 완전 베스팅
} else {
    uint256 elapsedSinceCliff = timestamp - (startTimestamp + CLIFF_DURATION);
    return (totalAllocation * elapsedSinceCliff) / VESTING_DURATION;  // Case C: 선형 베스팅
}
```

수학적 표현:

```
         { 0                                          if t < S + C
v(t) =  { T * (t - S - C) / V                        if S + C <= t < S + C + V
         { T                                          if t >= S + C + V

여기서: S = startTimestamp, C = CLIFF_DURATION, V = VESTING_DURATION, T = totalAllocation
```

이는 표준 cliff + linear vesting 수식이며 수학적으로 올바르다.

### 3.3 주요 시점별 계산

startTimestamp = 0 가정:

| 시점 | 경과일 | elapsedSinceCliff | 베스팅 금액 (PLM) | 비율 |
|------|--------|-------------------|-------------------|------|
| Genesis | 0일 | cliff | 0 | 0.00% |
| 3개월 | 90일 | cliff | 0 | 0.00% |
| 6개월 (cliff 종료) | 180일 | 0초 | 0 | 0.00% |
| 6개월 + 1일 | 181일 | 86,400초 | 44,177.78 | 0.09% |
| 12개월 | 360일 | 180일 | 7,952,000 | 16.67% |
| 18개월 | 540일 | 360일 | 15,904,000 | 33.33% |
| 24개월 | 720일 | 540일 | 23,856,000 | 50.00% |
| 30개월 | 900일 | 720일 | 31,808,000 | 66.67% |
| 36개월 | 1080일 | 900일 | 39,760,000 | 83.33% |
| 42개월 (완료) | 1260일 | - | 47,712,000 | 100.00% |

### 3.4 정밀도 분석

**오버플로우 검사**:
```
totalAllocation * (VESTING_DURATION - 1)
= 47,712,000 * 10^18 * 93,311,999
= 4.45 * 10^33

uint256 max = 1.16 * 10^77

비율: 3.84 * 10^-44 (안전)
```

**반올림 오차**:
```
최대 오차 = VESTING_DURATION - 1 = 93,311,999 wei
= 0.000000000093312 PLM
= 총량의 1.96 * 10^-16% (무시 가능)
```

**단조 증가(Monotonicity)**:
```
totalAllocation / VESTING_DURATION = 511,316,872,427,983,539 wei/초
>> 1이므로 매 초마다 최소 이 만큼 베스팅됨 (단조 증가 보장)
```

**완료 시점 정확성**: `t >= start + CLIFF + VESTING`일 때 `totalAllocation`을 직접 반환하므로 나눗셈 없이 정확함.

**Result: PASS** - 수식, 정밀도, 경계값 모두 정확

---

## 4. TeamVesting Math (팀 베스팅 수학)

**파일**: `/Users/jskim/Desktop/vibe/plumise-contracts/src/TeamVesting.sol`

### 4.1 파라미터 검증

| 파라미터 | 값 | Solidity 상수 |
|----------|-----|---------------|
| totalAllocation | 23,856,000 PLM | `23_856_000 ether` |
| CLIFF_DURATION | 365일 | `365 days` = 31,536,000초 |
| VESTING_DURATION | 1095일 | `1095 days` = 94,608,000초 |
| 총 기간 | 1460일 (48개월, 4년) | CLIFF + VESTING |

### 4.2 수식 검증

코드 (`_vestedAmount`, 라인 151-162):

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

FoundationTreasury와 동일한 수학적 구조이며, `totalAllocation` 대신 개별 beneficiary의 `allocation`을 사용한다. 수학적으로 올바르다.

### 4.3 Allocation 오버플로우 보호

```solidity
require(totalAllocated + allocation <= totalAllocation, "Exceeds total allocation");
```

이 검사로 모든 beneficiary의 allocation 합계가 totalAllocation (23,856,000 PLM)을 초과할 수 없다. Solidity 0.8.20의 built-in overflow check와 함께 이중 보호된다.

### 4.4 주요 시점별 계산 (5,000,000 PLM 할당 가정)

| 시점 | elapsedSinceCliff | 베스팅 금액 (PLM) | 비율 |
|------|-------------------|-------------------|------|
| Day 0 (genesis) | cliff | 0 | 0.00% |
| Day 365 (cliff 종료) | 0일 | 0 | 0.00% |
| Day 366 (cliff+1일) | 1일 | 4,566.21 | 0.09% |
| Day 730 (24개월) | 365일 | 1,666,666.67 | 33.33% |
| Day 1095 (36개월) | 730일 | 3,333,333.33 | 66.67% |
| Day 1460 (48개월, 완료) | - | 5,000,000.00 | 100.00% |

### 4.5 정밀도 분석

```
최대 곱: 23,856,000 * 10^18 * 94,607,999 = 2.26 * 10^33 (uint256 범위 내)
최대 반올림 오차: 94,607,999 wei = 0.000000000094608 PLM (무시 가능)
```

### 4.6 removeBeneficiary 회계 정확성

```solidity
totalAllocated -= b.allocation;  // 원래 allocation 전체를 차감
```

이미 release된 토큰은 전송 완료되었고, `totalAllocated`에서 원래 allocation 전체를 차감하므로 회계적으로 올바르다.

**Result: PASS** - 수식, 오버플로우 보호, 회계 로직 모두 정확

---

## 5. EcosystemFund Rate Limit (생태계 기금 Rate Limit)

**파일**: `/Users/jskim/Desktop/vibe/plumise-contracts/src/EcosystemFund.sol`

### 5.1 Rate Limit 계산

```solidity
uint256 maxAmount = (totalAllocation * RATE_LIMIT_PERCENT) / 100;
// = (55,664,000 * 10^18 * 5) / 100
// = 278,320,000 * 10^18 / 100
// = 2,783,200 * 10^18
// = 2,783,200 PLM
```

### 5.2 정밀도 검증

```
55,664,000 * 10^18 * 5 = 278,320,000,000,000,000,000,000,000
278,320,000,000,000,000,000,000,000 % 100 = 0

정밀도 손실: ZERO (완벽한 정수 나눗셈)
```

### 5.3 Timelock 검증

```
TIMELOCK_DURATION = 24 hours = 86,400 seconds (Solidity 'hours' 키워드 사용)
```

### 5.4 최대 인출 속도 분석

```
1회 최대: 2,783,200 PLM (총량의 5%)
최소 간격: 24시간
전체 인출에 걸리는 시간: 55,664,000 / 2,783,200 = 20일
```

### 5.5 설계 특성

- Rate limit는 **totalAllocation** (초기 금액) 기준이며, 현재 잔액 기준이 아님
- 잔액이 줄어도 rate limit는 변하지 않음 (고정 2,783,200 PLM)
- `transferBatch()`도 전체 합계에 대해 동일한 rate limit 적용
- Emergency mode 활성화 시 rate limit + timelock 모두 해제

**Result: PASS** - Rate limit 계산 정확, 정밀도 손실 없음

---

## 6. RewardPool Epoch Math (보상 풀 Epoch 수학)

**파일**: `/Users/jskim/Desktop/vibe/plumise-contracts/src/RewardPool.sol`

### 6.1 Epoch 계산

```solidity
uint256 public constant BLOCKS_PER_EPOCH = 1200;

function getCurrentEpoch() public view returns (uint256) {
    return (block.number - deployBlock) / BLOCKS_PER_EPOCH;
}
```

```
1200 blocks * 3 sec/block = 3,600 sec = 1 hour/epoch
```

| block.number | epoch | epoch 내 블록 |
|-------------|-------|---------------|
| 0 | 0 | 0 |
| 1199 | 0 | 1199 |
| 1200 | 1 | 0 |
| 2400 | 2 | 0 |
| 12000 | 10 | 0 |

### 6.2 Score 계산

```solidity
function calculateScore(Contribution memory contribution) internal view returns (uint256) {
    return
        contribution.taskCount * taskWeight +
        contribution.uptimeSeconds * uptimeWeight +
        contribution.responseScore * responseWeight;
}
```

기본 가중치: `taskWeight=50, uptimeWeight=30, responseWeight=20` (합계 100)

수학적 표현: `score = T*w_t + U*w_u + R*w_r` (가중 합산)

### 6.3 보상 분배 수식

```solidity
uint256 reward = (totalReward * score) / totalScore;
```

이는 표준 비례 분배(pro-rata distribution) 수식:

```
reward_i = floor(totalReward * score_i / totalScore)
```

### 6.4 오버플로우 분석

```
최대 epoch 보상: 10 PLM * 1200 blocks = 12,000 PLM = 12,000 * 10^18 wei
실제적 최대 score: ~160,000 (taskCount=1000, uptime=3600, response=100)

최대 곱: 12,000 * 10^18 * 160,000 = 1.92 * 10^27
uint256 max: 1.16 * 10^77

오버플로우: 불가 (안전)
```

### 6.5 Rounding Dust 분석

```
비례 분배 시 floor division으로 인해 dust 발생 가능
최대 dust = (agentCount - 1) wei per distribution
dust는 RewardPool 컨트랙트에 잔류 (분실 아님)
```

### 6.6 syncRewards 메커니즘

Geth의 `Finalize()`가 `state.AddBalance()`로 보상을 추가하면 `receive()`가 호출되지 않는다. `syncRewards()`가 `balance - lastTrackedBalance`로 미추적 보상을 감지한다.

```
receive(): epochRewards[epoch] += msg.value; lastTrackedBalance = balance;
syncRewards(): newRewards = balance - lastTrackedBalance; epochRewards[epoch] += newRewards;
claimReward(): lastTrackedBalance = balance; (인출 후 갱신)
```

이중 계산 방지가 올바르게 구현되어 있다.

### 6.7 주의사항

- **Score 오버플로우**: Oracle이 극단적으로 큰 값(예: `taskCount = 2^200`)을 보고하면 `taskCount * taskWeight`에서 오버플로우 가능. 단, Solidity 0.8.20의 built-in overflow check가 revert시키므로 자금 손실 위험은 없다. Oracle은 권한이 있는 주소만 호출 가능하므로 실제 위험도는 낮다.

**Result: PASS** - Epoch 계산, 비례 분배, sync 메커니즘 모두 정확

---

## 7. Wei Conversion Verification (Wei 변환 검증)

### 7.1 각 주소별 검증

| 주소 | PLM | 계산 (PLM * 10^18) | Genesis 값 | 일치 |
|------|-----|--------------------|------------|------|
| 0x1001 | 47,712,000 | 47712000000000000000000000 | 47712000000000000000000000 | PASS |
| 0x1002 | 55,664,000 | 55664000000000000000000000 | 55664000000000000000000000 | PASS |
| 0x1003 | 23,856,000 | 23856000000000000000000000 | 23856000000000000000000000 | PASS |
| 0x1004 | 31,808,000 | 31808000000000000000000000 | 31808000000000000000000000 | PASS |

### 7.2 자릿수 검증

모든 값이 26자리 (8자리 PLM + 18자리 10^18 소수점):
```
47,712,000 = 8자리
10^18 = 18개의 0
총: 26자리 (선행 0 없음)
```

### 7.3 Solidity `ether` 키워드 검증

컨트랙트에서 `47_712_000 ether`는 Solidity에서 `47_712_000 * 10^18`과 동일하다. Genesis JSON의 balance 값과 일치한다.

**Result: PASS** - 모든 Wei 변환 정확

---

## 8. 추가 보안 분석

### 8.1 Reentrancy 보호

모든 컨트랙트가 OpenZeppelin `ReentrancyGuard`를 사용하며, 외부 호출(`call{value:}`) 전에 상태 변경을 수행한다 (CEI 패턴):

- **FoundationTreasury**: `released += releasable` 후 `call{value:}` (라인 48-49)
- **TeamVesting**: `beneficiaries[beneficiary].released += releasable` 후 `call{value:}` (라인 110-112)
- **RewardPool**: `pendingRewards[msg.sender] = 0` 후 `call{value:}` (라인 200-203) -- CEI 패턴 + nonReentrant
- **EcosystemFund**: `lastTransferTimestamp = block.timestamp` 후 `call{value:}` (라인 62-64)

### 8.2 접근 제어

| 컨트랙트 | 핵심 함수 | 제한 |
|----------|-----------|------|
| FoundationTreasury | release() | onlyOwner |
| EcosystemFund | transfer(), transferBatch() | onlyOwner |
| TeamVesting | addBeneficiary(), removeBeneficiary() | onlyOwner |
| TeamVesting | release() | 누구나 호출 가능 (안전: 토큰은 beneficiary에게 전송) |
| LiquidityDeployer | transfer() | onlyOwner |
| RewardPool | reportContribution() | oracle only |
| RewardPool | setOracle(), setRewardFormula() | onlyOwner |
| RewardPool | claimReward() | 등록된 에이전트만 |

### 8.3 Solidity 버전

모든 컨트랙트가 `pragma solidity 0.8.20`을 사용하며, built-in overflow/underflow check가 활성화되어 있다.

---

## Final Verdict (최종 판정)

| 검증 항목 | 결과 |
|-----------|------|
| 1. Total Supply (10억 PLM) | **PASS** |
| 2. Genesis Distribution (159,040,000 PLM, 비율 정확) | **PASS** |
| 3. FoundationTreasury Vesting (6m cliff + 36m linear) | **PASS** |
| 4. TeamVesting Math (12m cliff + 36m linear) | **PASS** |
| 5. EcosystemFund Rate Limit (5%, 24h timelock) | **PASS** |
| 6. RewardPool Epoch Math (1200 blocks/epoch, 비례 분배) | **PASS** |
| 7. Wei Conversion (모든 genesis 값) | **PASS** |

### 전체 결과: ALL PASS

### 발견된 이슈: 없음 (Critical/High/Medium)

### 참고사항 (Low/Informational):

1. **EcosystemFund Rate Limit 기준**: totalAllocation(초기값) 기준이므로, 잔액이 매우 적을 때도 rate limit가 2,783,200 PLM으로 유지됨. 잔액 < rate limit일 경우 `address(this).balance >= amount` 체크로 자연스럽게 제한됨.

2. **RewardPool Score 오버플로우**: Oracle이 극단적 값을 보고하면 Solidity 0.8.20의 overflow check로 revert됨. 자금 손실 위험은 없으나, oracle 구현 시 적절한 범위 검증이 권장됨.

3. **Rounding Dust**: 모든 비례 분배에서 floor division으로 인한 미세한 dust가 컨트랙트에 잔류할 수 있음. 이는 의도된 동작이며, 금액은 wei 단위로 무시 가능.

4. **반감기 정밀도**: 42,048,000 blocks * 3초 = 3.997년 (365.25일 기준). 정확히 4년은 아니지만 이는 블록 기반 반감기의 표준적 특성임 (Bitcoin도 동일).

---

*검증 완료. 모든 수학적 계산이 정확하며, Genesis 임베딩에 적합합니다.*

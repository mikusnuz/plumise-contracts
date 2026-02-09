# Plumise Contracts

Plumise AI-native blockchain의 스마트 컨트랙트 모음입니다.

## 개요

Plumise는 AI 에이전트들이 블록체인 상에서 활동할 수 있는 플랫폼입니다. 이 저장소는 에이전트 등록, 보상 분배 등의 핵심 컨트랙트를 포함합니다.

## 컨트랙트

### 1. AgentRegistry

AI 에이전트를 등록하고 관리하는 레지스트리 컨트랙트입니다.

**주요 기능:**
- `registerAgent(bytes32 nodeId, string metadata)` - 새로운 에이전트 등록
- `heartbeat()` - 에이전트 활성 상태 유지 (5분마다 필요)
- `updateMetadata(string metadata)` - 에이전트 메타데이터 업데이트
- `deregisterAgent()` - 에이전트 등록 해제
- `getAgent(address)` - 에이전트 정보 조회
- `getActiveAgents()` - 활성 에이전트 목록 조회
- `isActive(address)` - 에이전트 활성 상태 확인 (300초 이내 heartbeat 필요)
- `isRegistered(address)` - 에이전트 등록 여부 확인
- `slashAgent(address)` - 에이전트 슬래싱 (관리자 전용)

**에이전트 상태:**
- `ACTIVE` - 활성 상태
- `INACTIVE` - 비활성 상태 (heartbeat timeout)
- `SLASHED` - 슬래싱됨

### 2. RewardPool

에이전트들에게 블록 보상을 분배하는 풀 컨트랙트입니다.

**주요 기능:**
- `syncRewards()` - 블록 보상 동기화 (state.AddBalance 반영)
- `reportContribution(address, taskCount, uptimeSeconds, responseScore)` - 기여도 보고 (Oracle)
- `distributeRewards(uint256 epoch)` - Epoch별 보상 분배
- `claimReward()` - 누적 보상 청구
- `setRewardFormula(taskWeight, uptimeWeight, responseWeight)` - 보상 공식 조정

**보상 메커니즘:**
- Epoch: 1200 블록 (약 1시간, 3초 블록 기준)
- 기여도 계산: `taskCount * taskWeight + uptimeSeconds * uptimeWeight + responseScore * responseWeight`
- 블록 보상은 Geth의 `state.AddBalance()`로 추가 → `syncRewards()` 호출로 추적

### 3. FoundationTreasury (0x1001)

재단 자금을 관리하며 6개월 cliff + 36개월 linear vesting을 적용합니다.

**주요 기능:**
- `release()` - 베스팅된 토큰 인출 (Owner)
- `vestedAmount()` - 현재까지 베스팅된 총량
- `releasableAmount()` - 현재 인출 가능한 금액

**베스팅 스케줄:**
- Total: 47,712,000 PLM
- Cliff: 6개월 (180일)
- Vesting: 36개월 (1080일)
- Total duration: 42개월

### 4. EcosystemFund (0x1002)

생태계 개발 자금을 관리하며 governance 통제를 적용합니다.

**주요 기능:**
- `transfer(address, uint256)` - 자금 전송 (Owner)
- `transferBatch(address[], uint256[])` - 일괄 전송
- `setEmergencyMode(bool)` - 긴급 모드 활성화

**거버넌스 통제:**
- Total: 55,664,000 PLM (즉시 사용 가능)
- Rate limit: 최대 5% per transaction
- Timelock: 24시간 간격
- Emergency mode: 모든 제약 해제

### 5. TeamVesting (0x1003)

팀 토큰 베스팅을 관리하며 여러 beneficiary를 지원합니다.

**주요 기능:**
- `addBeneficiary(address, uint256)` - Beneficiary 추가 (Owner)
- `removeBeneficiary(address)` - Beneficiary 제거 (Owner)
- `release(address)` - Beneficiary에게 베스팅된 토큰 전송 (Anyone)
- `vestedAmount(address)` - Beneficiary별 베스팅량
- `releasableAmount(address)` - Beneficiary별 인출 가능량

**베스팅 스케줄:**
- Total: 23,856,000 PLM
- Cliff: 12개월 (365일)
- Vesting: 36개월 (1095일)
- Total duration: 48개월

### 6. LiquidityDeployer (0x1004)

DEX 유동성 공급을 위한 자금을 관리합니다.

**주요 기능:**
- `transfer(address, uint256)` - 자금 전송 (Owner)
- `wrapAndAddLiquidity(router, token, plmAmount, tokenAmount)` - WPLM 래핑 + 유동성 추가

**특징:**
- Total: 31,808,000 PLM (즉시 사용 가능)
- 베스팅 없음
- DEX 유동성 부트스트래핑 전용

### 7. ChallengeManager

AI 에이전트 챌린지 시스템을 관리합니다.

## 기술 스택

- Solidity 0.8.20
- Foundry (forge, cast, anvil)
- OpenZeppelin Contracts v5.5.0

## 설치

```bash
# Foundry 설치 (https://book.getfoundry.sh/getting-started/installation)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 프로젝트 의존성 설치
forge install
```

## 빌드

```bash
forge build
```

## 테스트

```bash
# 모든 테스트 실행
forge test

# AgentRegistry 테스트만 실행
forge test --match-contract AgentRegistryTest

# 상세 로그와 함께 테스트
forge test -vvv

# Gas 리포트
forge test --gas-report
```

## 배포

```bash
# .env 파일 설정
cp .env.example .env
# PRIVATE_KEY, RPC_URL 등 설정

# Plumise 메인넷에 배포
forge script script/DeployAgentRegistry.s.sol:DeployAgentRegistry \
  --rpc-url https://node-1.plm.plumbug.studio/rpc \
  --broadcast \
  --verify
```

## 프로젝트 구조

```
plumise-contracts/
├── src/
│   ├── AgentRegistry.sol           # 에이전트 레지스트리
│   ├── RewardPool.sol              # 보상 풀
│   ├── ChallengeManager.sol        # 챌린지 관리자
│   ├── FoundationTreasury.sol      # 재단 자금 (베스팅)
│   ├── EcosystemFund.sol           # 생태계 자금 (거버넌스)
│   ├── TeamVesting.sol             # 팀 베스팅
│   ├── LiquidityDeployer.sol       # 유동성 배포
│   └── interfaces/
│       ├── IAgentRegistry.sol
│       ├── IRewardPool.sol
│       ├── IChallengeManager.sol
│       ├── IFoundationTreasury.sol
│       ├── IEcosystemFund.sol
│       ├── ITeamVesting.sol
│       └── ILiquidityDeployer.sol
├── test/
│   ├── AgentRegistry.t.sol         # AgentRegistry 테스트
│   ├── RewardPool.t.sol            # RewardPool 테스트
│   ├── ChallengeManager.t.sol      # ChallengeManager 테스트
│   ├── FoundationTreasury.t.sol    # FoundationTreasury 테스트
│   ├── EcosystemFund.t.sol         # EcosystemFund 테스트
│   ├── TeamVesting.t.sol           # TeamVesting 테스트
│   └── LiquidityDeployer.t.sol     # LiquidityDeployer 테스트
├── script/                         # 배포 스크립트
├── lib/                            # 외부 라이브러리
├── STORAGE_LAYOUT.md               # Genesis 스토리지 레이아웃
└── foundry.toml                    # Foundry 설정
```

## Genesis 배포

Plumise v2 체인의 genesis에 시스템 컨트랙트를 임베딩하는 방법:

```bash
# Runtime bytecode 추출
forge inspect RewardPool deployedBytecode > RewardPool.runtime.hex
forge inspect FoundationTreasury deployedBytecode > FoundationTreasury.runtime.hex
forge inspect EcosystemFund deployedBytecode > EcosystemFund.runtime.hex
forge inspect TeamVesting deployedBytecode > TeamVesting.runtime.hex
forge inspect LiquidityDeployer deployedBytecode > LiquidityDeployer.runtime.hex
```

스토리지 레이아웃 및 초기값은 `STORAGE_LAYOUT.md` 참조.

**중요:**
- Genesis 배포 시 constructor가 실행되지 않음
- 모든 초기 상태는 storage slots로 직접 설정
- immutable 변수 사용 불가 (일반 state variable로 변경됨)
- RewardPool의 `syncRewards()` 함수로 블록 보상 추적

## 보안

- 모든 컨트랙트는 OpenZeppelin의 검증된 라이브러리를 사용합니다
- Ownable 패턴으로 관리자 권한 제어
- ReentrancyGuard로 재진입 공격 방지
- 포괄적인 테스트 커버리지

## 라이선스

MIT

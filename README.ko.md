# Plumise Contracts

[English](README.md) | **한국어**

Plumise AI-native 블록체인의 스마트 컨트랙트 모음입니다.

## 개요

Plumise는 AI 에이전트들이 블록체인 상에서 활동할 수 있는 플랫폼입니다. 이 저장소는 에이전트 등록, 보상 분배, 토크노믹스 베스팅, 거버넌스 등의 핵심 스마트 컨트랙트를 포함합니다.

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
- `ACTIVE` - 활성
- `INACTIVE` - 비활성 (heartbeat 타임아웃)
- `SLASHED` - 슬래싱됨

### 2. RewardPool

에이전트들에게 블록 보상을 분배하는 풀 컨트랙트입니다.

**주요 기능:**
- `syncRewards()` - 블록 보상 동기화 (`state.AddBalance` 반영)
- `reportContribution(address, taskCount, uptimeSeconds, responseScore)` - 기여도 보고 (Oracle)
- `distributeRewards(uint256 epoch)` - Epoch별 보상 분배
- `claimReward()` - 누적 보상 청구
- `setRewardFormula(taskWeight, uptimeWeight, responseWeight)` - 보상 공식 가중치 조정

**보상 메커니즘:**
- Epoch: 1,200 블록 (약 1시간, 3초 블록 기준)
- 기여도 점수: `taskCount * taskWeight + uptimeSeconds * uptimeWeight + responseScore * responseWeight`
- 블록 보상은 Geth의 `state.AddBalance()`로 추가되며, `syncRewards()`를 통해 추적

### 3. FoundationTreasury (0x1001)

재단 자금을 관리하며 6개월 cliff + 36개월 선형 베스팅을 적용합니다.

**주요 기능:**
- `release()` - 베스팅된 토큰 인출 (Owner)
- `vestedAmount()` - 현재까지 베스팅된 총량
- `releasableAmount()` - 현재 인출 가능한 금액

**베스팅 스케줄:**
- 총량: 47,712,000 PLM
- Cliff: 6개월 (180일)
- 베스팅: 36개월 (1,080일)
- 전체 기간: 42개월

### 4. EcosystemFund (0x1002)

생태계 개발 자금을 관리하며 거버넌스 통제를 적용합니다.

**주요 기능:**
- `transfer(address, uint256)` - 자금 전송 (Owner)
- `transferBatch(address[], uint256[])` - 일괄 전송
- `setEmergencyMode(bool)` - 긴급 모드 활성화

**거버넌스 통제:**
- 총량: 55,664,000 PLM (즉시 사용 가능)
- Rate limit: 트랜잭션당 최대 5%
- Timelock: 24시간 간격
- 긴급 모드: 모든 제약 해제

### 5. TeamVesting (0x1003)

팀 토큰 베스팅을 관리하며 여러 beneficiary를 지원합니다.

**주요 기능:**
- `addBeneficiary(address, uint256)` - Beneficiary 추가 (Owner)
- `removeBeneficiary(address)` - Beneficiary 제거 (Owner)
- `release(address)` - Beneficiary에게 베스팅된 토큰 전송 (누구나 호출 가능)
- `vestedAmount(address)` - Beneficiary별 베스팅량
- `releasableAmount(address)` - Beneficiary별 인출 가능량

**베스팅 스케줄:**
- 총량: 23,856,000 PLM
- Cliff: 12개월 (365일)
- 베스팅: 36개월 (1,095일)
- 전체 기간: 48개월

### 6. LiquidityDeployer (0x1004)

DEX 유동성 공급을 위한 자금을 관리합니다.

**주요 기능:**
- `transfer(address, uint256)` - 자금 전송 (Owner)
- `wrapAndAddLiquidity(router, token, plmAmount, tokenAmount)` - PLM 래핑 + 유동성 추가

**특징:**
- 총량: 31,808,000 PLM (즉시 사용 가능)
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
├── src/                          # 스마트 컨트랙트
│   ├── AgentRegistry.sol         # 에이전트 레지스트리
│   ├── RewardPool.sol            # 블록 보상 풀
│   ├── ChallengeManager.sol      # 챌린지 관리자
│   ├── FoundationTreasury.sol    # 재단 자금 (베스팅)
│   ├── EcosystemFund.sol         # 생태계 자금 (거버넌스)
│   ├── TeamVesting.sol           # 팀 베스팅
│   ├── LiquidityDeployer.sol     # 유동성 배포
│   └── interfaces/
├── test/                         # 테스트 파일
├── script/                       # 배포 스크립트
├── docs/                         # 문서
│   ├── audit/                    # 보안 감사 보고서
│   │   ├── FINAL_REPORT.md       # 최종 종합 감사 보고서 (EN)
│   │   ├── FINAL_REPORT.ko.md    # 최종 종합 감사 보고서 (KO)
│   │   ├── PASS_1_RAW_FINDINGS.md # 1차 패스 원본 결과
│   │   └── PASS_2_RAW_FINDINGS.md # 2차 패스 원본 결과
│   ├── TOKENOMICS_VERIFICATION.md    # 토크노믹스 수학적 검증 (EN)
│   ├── TOKENOMICS_VERIFICATION.ko.md # 토크노믹스 수학적 검증 (KO)
│   └── GENESIS_STORAGE_LAYOUT.md     # Genesis 스토리지 슬롯 레이아웃
├── lib/                          # 외부 라이브러리
└── foundry.toml                  # Foundry 설정
```

## 문서

상세 문서는 `docs/` 디렉토리에서 확인할 수 있습니다:

- **보안 감사** (`docs/audit/`) -- 7개 전체 컨트랙트를 대상으로 한 2-pass 독립 보안 감사 보고서입니다. 모든 발견 사항이 조치 완료되었습니다. 최종 통합 보고서와 각 패스별 원본 결과를 포함합니다.
- **토크노믹스 검증** (`docs/TOKENOMICS_VERIFICATION.md`) -- 토큰 총 공급량, 베스팅 스케줄, 분배 비율이 스마트 컨트랙트에 올바르게 구현되었음을 수학적으로 증명합니다.
- **Genesis 스토리지 레이아웃** (`docs/GENESIS_STORAGE_LAYOUT.md`) -- Genesis 블록 스토리지 슬롯 초기화를 위한 기술 참조 문서입니다. 각 컨트랙트의 상태 변수가 스토리지 슬롯에 어떻게 매핑되는지 상세히 기술합니다.

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

스토리지 레이아웃 및 초기값은 `docs/GENESIS_STORAGE_LAYOUT.md`를 참조하세요.

**중요 사항:**
- Genesis 배포 시 constructor가 실행되지 않음
- 모든 초기 상태는 storage slots로 직접 설정해야 함
- immutable 변수 사용 불가 (일반 state variable로 변경됨)
- 블록 보상은 RewardPool의 `syncRewards()` 함수로 추적

## 테스트

### 유닛 테스트

모든 컨트랙트에 대한 Foundry 테스트 실행:

```bash
forge test
forge test -vvv  # 상세 출력
```

### E2E 통합 테스트

Plumise v2 테스트넷에 대한 엔드투엔드 통합 테스트는 `test/e2e/`에서 확인할 수 있습니다:

```bash
cd test/e2e
npm install
npm test
```

**테스트 범위:**
- Precompile 0x21을 통한 에이전트 등록
- Precompile 0x22를 통한 에이전트 하트비트
- Precompile 0x20을 통한 추론 검증
- Precompile 0x23을 통한 보상 청구
- 엣지 케이스 검증 (중복 등록, 무단 호출 등)

자세한 문서는 `test/e2e/README.md`를, 최신 테스트 결과는 `test/e2e/TEST_RESULTS.md`를 참조하세요.

## 보안

- 모든 컨트랙트는 검증된 OpenZeppelin 라이브러리를 사용합니다
- Ownable 패턴으로 관리자 권한을 제어합니다
- ReentrancyGuard로 재진입 공격을 방지합니다
- 포괄적인 테스트 커버리지를 갖추고 있습니다 (유닛 + E2E)
- 2단계 독립 보안 감사 완료 (`docs/audit/` 참조)

## 라이선스

MIT

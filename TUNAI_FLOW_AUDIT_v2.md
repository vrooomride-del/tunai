# TUNAI / TUNAI Pro — 파인튠 플로우 전체 진단 v2

> 작성일: 2026-06-20 (2차 세션)  
> 진단 범위: 6단계 전체 최종 상태표  
> 코드 수정 없음 — 진단 전용

---

## 6단계 전체 상태표

| 단계 | 기능 | 모바일 | Pro | 상태 |
|---|---|---|---|---|
| **1** | DSP 보드 자동 탐지 | ❌ | ❌ | 수동 선택만 |
| **2** | 유닛 물성 기반 크로스오버 제안 | ❌ | ✅ 부분 | Pro만 구현, 위상/감도 매칭 없음 |
| **3** | SafetyProfile (T/S 기반 HPF + gain 클램핑) | ✅ | ✅ | 완료 |
| **4** | AI APPLY (추천 → DSP 전송) | ✅ | ✅ | 완료 |
| **5** | 폰용 Pro 모드 | - | - | 이번 세션 범위 외 |
| **6** | 커뮤니티 인클로저 해시 매칭 | ❌ | - | API 파라미터만 존재, 생성/검색 미구현 |

---

## 1단계: DSP 보드 자동 탐지

**상태: 탐지 기능 없음 (수동 선택)**

- BLE 연결 시 `fff0` 서비스 UUID로 연결 여부만 확인
- ADAU1701 vs ADAU1466 구분 로직 없음 — `systemProfileProvider` 에 사용자가 직접 선택
- `Adau1466Adapter`: 5개 메서드 전부 `UnimplementedError` → 파란보드로 실제 DSP 쓰기 불가
- `isAdau1466` getter 존재하지만 런타임 auto-detect에 미사용

**갭**: BLE 연결 → 서비스/캐릭터리스틱 기반으로 보드 종류 자동 식별하는 코드 없음.  
구현하려면 ICP5 보드 특유의 UUID 또는 read characteristic 값으로 구별해야 함.

---

## 2단계: 유닛 물성 기반 크로스오버 제안

**상태: Pro 부분구현, 모바일 없음**

### Pro 구현 내용

**화면**: DRIVER & SYSTEM (3탭)
- `DRIVERS` 탭: FRD/ZMA 임포트, + WOOFER/TWEETER/MID 추가
- `ENCLOSURE` 탭: 박스 타입/체적/포트 입력 → 포트 공진(Fb) 자동 계산
- `CROSSOVER` 탭: 주파수 입력 + AUTO 버튼 + 필터 타입 선택 → DSP 전송

**AUTO 버튼 로직** (`driver_screen.dart:_autoCalc()`):
```
1순위: FRD 양쪽 → FrdParser.recommendCrossover()
   → 우퍼 -6dB 롤오프 + 트위터 -6dB 하한 → 기하평균 sqrt(f_w × f_t)

2순위: T/S만 있을 때 → 우퍼 Fs × (3~5), Qts 조건부
   - Qts < 0.3 → ×3
   - Qts < 0.5 → ×4
   - 나머지 → ×5
   - 결과 500~5000Hz 클램프

3웨이: wooferFs×4 (하단), midFs×4 (상단)
```

**ZMA → T/S 역산** (`frd_parser.dart:extractTs()`):
- Fs: 임피던스 최대값 주파수
- Re: 200-1000Hz 최소 임피던스
- Qms/Qes/Qts: f1/f2 표준 -3dB 반전법
- Vas: 미구현 (별도 입력 필요로 표기만 됨)

**필터 타입 계수** (`dsp_engine.dart:calculateCrossoverBiquads()`):
- LR12/LR24/LR48, BW12/BW24 — Biquad 계수 완전 구현
- DSP 채널별 LP/HP 분기 → ADAU1701에서 실제 전송 동작

**FRD 그래프**: 로드 후 log 주파수 축 Bode plot 표시 (`_FrdGraph`)

### 모바일 상태

- `SpeakerProfile`: fs/qts/vas/xmax/sensitivity 필드 있음
- `recommendedHpfFreq = fs * 0.85` — 단순 HPF 1개만
- 사용자 T/S 입력 UI: **없음** (tunai_one 고정 프리셋 선택 or skip)
- 크로스오버 UI: **없음**

### 갭 (사업 핵심 관점)

| 항목 | Pro | 모바일 |
|---|---|---|
| FRD 임포트 + 파싱 | ✅ | ❌ |
| ZMA → T/S 역산 | ✅ | ❌ |
| 크로스오버 자동 추천 (FRD 기반) | ✅ | ❌ |
| 크로스오버 자동 추천 (T/S 기반) | ✅ | ❌ |
| 필터 타입 선택 (LR/BW) | ✅ | ❌ |
| DSP 전송 | ✅ ADAU1701 | ❌ |
| 위상 정합 (acoustic delay) | ❌ | ❌ |
| 감도 자동 매칭 (채널 간 gain) | ❌ | ❌ |
| Vas 입력 경로 | ❌ | ❌ |

**"VituixCAD 없이 폰으로 크로스오버"** 슬로건 달성도:
- Pro: 70% — FRD/T/S 기반 자동 추천 + 필터 선택 + DSP 전송까지 동작. 단 위상 정합/감도 매칭 없음
- 모바일: 0% — 크로스오버 관련 기능 전무

---

## 3단계: SafetyProfile (HPF + Gain 클램핑)

**상태: 완료**

- `SafetyProfile.fromTs()`: Fs × 0.85 = HPF 주파수, Xmax 기반 maxBassBoost
- 모바일: `DspCompilerSafety.safetyFromTs()` → `clampBassBoost()` → `compileHpf()` → APPLY DSP에 prepend
- Pro: `SafetyProfile.fromTs()` → `clampBassBoost()` DSP 컴파일 시 적용
- `SpeakerProfileSelector` 모두 존재

---

## 4단계: AI APPLY

**상태: 완료**

- 모바일: Firebase Functions `aiTune` callable → `AiTuningResult.bands` → 밴드별 APPLY + APPLY ALL BLE 전송
- Pro: AI → `dspProvider` PEQ 업데이트 → SEND TO DSP (isDirty 강조)
- 양쪽 모두 systemProfile 컨텍스트 AI에 전달

---

## 6단계: 커뮤니티 인클로저 해시 매칭

**상태: API 파라미터만 존재, 클라이언트 미구현**

- `ApiService.getPresets({String? hash})` → `?hash=xxx` 서버 지원 ✅
- `ApiService.uploadPreset(..., String? enclosureHash)` → `enclosure_hash` 서버 지원 ✅
- 실제 업로드 호출: `enclosureHash: null, fps: []` — 해시값 전달 없음 ❌
- 검색: 해시 없이 전체 목록 조회 — 매칭 없음 ❌
- 인클로저 해시 생성 함수: **없음** ❌

**결론**: 특허 청구항 8 "인클로저 기하학적 식별 해시" 기반 매칭은 완전 미구현.  
현재 동작: 단순 게시판 (trending/latest 정렬만)

---

## 다음 세션 우선순위

| 순위 | 작업 | 레포 | 난이도 |
|---|---|---|---|
| P1 | **ADAU1466 SigmaStudio 주소맵 확정 → 어댑터 구현** | 양쪽 | 하드웨어 필요 |
| P2 | **모바일 크로스오버 UI** — T/S 직접 입력 + crossover 추천 + HPF/LP DSP 전송 | 모바일 | 중간 |
| P3 | **위상 정합 (acoustic delay)** — 트위터/미드 거리 입력 → delay 자동 계산 → DSP | Pro | 중간 |
| P4 | **감도 자동 매칭** — FRD 감도 차이 → 채널 gain 보정 → DSP | Pro | 작음 |
| P5 | **인클로저 해시 생성** — 체적/포트 파라미터 → SHA 해시 → upload/search 연결 | 모바일 | 작음 |
| P6 | **Vas 입력 경로** — SpeakerProfileSelector에 Vas 필드 추가 | 양쪽 | 작음 |
| P7 | **ADAU1701 Gain/Delay PRAM 주소 확정** (`_gainBase=0x0000` TODO) | Pro | 하드웨어 필요 |

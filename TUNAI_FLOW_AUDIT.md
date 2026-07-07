# TUNAI Mobile — 파인튜닝 플로우 진단 보고서

> 진단일: 2026-06-20 / 코드 수정 없음, 읽기 전용 세션

---

## [1] 스피커/DSP 보드 탐지

- **상태**: 구현완료
- **관련 파일**:
  - `lib/core/profiles/system_profile.dart`
  - `lib/core/dsp/dsp_adapter.dart`
  - `lib/core/dsp/adau1701_adapter.dart`
  - `lib/core/dsp/adau1466_adapter.dart`
  - `lib/features/home/home_screen.dart` (`_SpeakerSelectPanel`)
- **설명**: `SystemProfileId` enum으로 JAB4(ADAU1701), Isobarik(ADAU1466), TUNAI REFERENCE(ADAU1466) 3종을 정의. HomeScreen `_SpeakerSelectPanel`에서 유저가 탭으로 수동 선택하는 UI 완성. `adapterFactory`로 DspAdapter 추상화 연결됨.
- **갭**:
  - BLE advertisement로 보드 종류를 **자동 식별**하는 로직 없음 — 유저가 반드시 수동 선택
  - ADAU1466 보드는 `isAdau1466` 플래그로 APPLY 버튼이 명시 비활성화 ("SigmaStudio 주소맵 미확정") → 고급형 보드 사용자는 DSP 전송 불가

---

## [2] T/S 파라미터 + 크로스오버 제안

- **상태**: 부분구현
- **관련 파일**:
  - `lib/core/speaker_profile.dart`
  - `lib/features/measurement/speaker_profile_selector.dart`
  - `lib/core/profiles/system_profile.dart` (`crossoverPoints` 필드)
- **설명**: `SpeakerProfile`에 Fs, Qts, Vas, Xmax, sensitivity, 인클로저 파라미터 모두 정의됨. `speaker_profile_selector.dart`에서 수동 입력 UI 구현. `SystemProfile`에 채널별 `freqRange`와 `crossoverPoints` 필드로 크로스오버 구성 정보 보유.
- **갭**:
  - 크로스오버 주파수 **자동 계산** (Qts 기반 알킨 공식 등) 없음
  - FRD(주파수 응답 데이터) **로드/파싱 기능 없음**
  - T/S에서 권장 크로스오버 주파수를 UI에 제안하는 로직 미연결
  - `lib/features/driver/` 폴더 자체가 존재하지 않음 (Pro에만 있음)

---

## [3] 안전 기본값 DSP 자동 적용

- **상태**: 부분구현 (계산 로직 존재, 실제 적용 경로 끊김)
- **관련 파일**:
  - `lib/features/dsp/dsp_compiler.dart` (`DspCompilerSafety`, `calculateHpf()`, `clampBassBoost()`)
  - `lib/features/measurement/measurement_controller.dart`
- **설명**: `DspCompilerSafety.safetyFromTs()`로 Xmax 기반 `maxBassBoost`와 HPF 주파수를 계산. `clampBassBoost()`로 200Hz 이하 피크 gain을 자동 클램핑. `calculateHpf()` biquad 계수 계산까지 완성.
- **갭**:
  - `calculateHpf()`가 `DspCompilerSafety`에 존재하지만 `MeasurementController`에서 **호출되지 않음** — 데드코드 상태
  - `HomeScreen`에서 `startMeasurement(speakerProfile: ...)` 호출 시 speakerProfile을 **넘기지 않아** 안전범위가 항상 스킵
  - 스피커 보호 기능이 "있는 것처럼 보이지만 작동하지 않는" 상태

---

## [4] 측정 → AI 튜닝 플로우

- **상태**: 부분구현 (표시만 되고 DSP 전송 미연결)
- **관련 파일**:
  - `lib/features/measurement/measurement_controller.dart`
  - `lib/features/home/home_screen.dart` (`_AiTunePanel`)
  - `lib/core/ai_tuning_service.dart`

**단계별 연결 현황**:

| 단계 | 연결 상태 |
|---|---|
| 측정 완료 → peaks/scmsBins 저장 | ✅ Riverpod `measurementProvider`로 전파 |
| HomeScreen AI 패널 활성화 | ✅ `step == done`일 때 `_AiTunePanel` 표시 |
| peaks → Firebase Functions 전송 | ✅ `AiTuningService.suggest(peaks, userRequest)` |
| AI 결과 화면 표시 | ✅ 밴드 제안 목록 표시 |
| AI 제안 → BLE 전송 (APPLY) | ❌ **버튼 없음** — 연결 완전 누락 |
| 전체 주파수 응답 AI 전달 | ❌ peaks 목록만 전송, scmsBins 미전달 |

- **갭**:
  - AI 제안 bands → `DspCompiler.compileAll()` → BLE 전송하는 **"APPLY AI" 버튼이 없음** — 핵심 결함
  - 전체 주파수 응답(scmsBins) 미전송으로 AI가 풀스펙트럼 분석 불가

---

## [5] 모바일 Pro 모드 가능성 (설계 검토)

- **상태**: 기반 구조 완성 (UI 없음)
- **관련 파일**:
  - `lib/core/dsp/dsp_adapter.dart` (writeBiquad, writeCrossover, writeDelay, writeGain, writeSubsonicFilter)
  - `lib/features/measurement/measurement_controller.dart`
- **설명**: `DspAdapter` 추상 클래스와 `CrossoverSlope` enum(bw2/bw4/lr2/lr4/lr8), `CrossoverConfig`가 모두 정의됨. MeasurementController는 StateNotifier 기반으로 파라미터 확장 용이.
- **갭**:
  - `DspAdapter.writeCrossover()` 등 고급 메서드가 HomeScreen/DspCompiler에서 **전혀 호출되지 않음** — 추상화만 존재
  - Pro 모드 전용 UI(파라메트릭 EQ 편집기, 크로스오버 주파수 슬라이더) 없음
  - **결론**: 기술적으로 Pro 모드 UI 추가는 가능한 구조. `dsp_engine.dart` + `dsp_adapter.dart`를 패키지로 추출하면 모바일↔Pro 코드 공유도 즉시 가능.

---

## [6] 커뮤니티/프리셋 공유

- **상태**: 구현완료 (서버 연동 포함)
- **관련 파일**:
  - `lib/features/community/community_screen.dart`
  - `lib/core/api_service.dart`
- **설명**: `api.tunai.kr` REST API 연동 완성. PRESETS 탭(인기순/최신순, GET으로 BLE 즉시 적용), BOARD 탭(자유/튜닝팁/리뷰/Q&A 게시판), 댓글, 좋아요, 다운로드 카운터 구현. `uploadPreset()`에 `price` 파라미터 있어 유료 판매 기반 코드 존재.
- **갭**:
  - 업로드 시 `fps: []` **빈 배열 하드코딩** — 실제 측정 데이터 첨부 미연결
  - 판매 기능(`price > 0`)은 API 파라미터만 있고 **UI에서 가격 설정 화면 없음**

---

## 다음 세션 우선순위 제안

| 순위 | 작업 | 이유 |
|---|---|---|
| P1 | **AI 제안 → DSP APPLY 버튼 연결** | AI 튜닝이 표시만 되고 실제 스피커에 반영 불가 — 핵심 결함 |
| P2 | **HPF SafetyProfile 실제 적용** | 계산 로직은 있으나 아무도 호출 안 함 — 스피커 보호 기능이 작동하지 않음 |
| P3 | **ADAU1466 SigmaStudio 주소맵 확정** | 고급형 보드 사용자 DSP 전송 완전 차단 상태 |
| P4 | **커뮤니티 업로드 시 측정 데이터 첨부** | `fps: []` 빈 배열로 프리셋 공유 시 실제 EQ 데이터 누락 |
| P5 | **AI에 전체 주파수 응답 전달** | 현재 peaks만 전달 → 스펙트럼 전체 컨텍스트 없이 AI 응답 |

# TUNAI 마스터플랜 현황판

> 이 표는 매 세션 시작/종료 시 갱신한다.
> 새 작업으로 새기 전에 반드시 먼저 읽고, 세션 끝나면 변경된 항목만 갱신해서 다음 HANDOFF.md에 그대로 옮긴다.

**업데이트: 2026-07-05 (AKG-ready Profile Model 추가 완료 — 항목 H. Gap analysis D/C/H+B 4개 항목 전체 마무리)**

---

## A. 앱 이름 및 포지셔닝 확정

| 앱 | 플랫폼 | 타겟 | 철학 |
|---|---|---|---|
| **TUNAI** | 모바일 (iOS/Android) | Consumer (일반 사용자) | 3분 안에 최고의 소리. AI가 주인공. |
| **TUNAI PRO** | macOS / Windows (별도 저장소 `tunai_pro`) | Engineer / Power User | DSP 설계 툴. 전문가용. |

---

## B. 제품 플로우 목표

### TUNAI 모바일 (Consumer) — ✅ 이번 세션에 재설계 완료
```
CONNECT → MEASURE → AI → LISTEN → FINE TUNE(MORE) → ADVANCED(MORE)
```
일반 사용자는 CONNECT~LISTEN 4탭만 쓰면 되고, FINE TUNE/ADVANCED/LIBRARY/COMMUNITY/PROFILE은
5번째 탭 MORE 안에 숨겨진다.

### TUNAI PRO (Engineer) — ⏸ 다음 세션 (별도 저장소 `tunai_pro`)
```
PROJECT → DRIVER → XO → PEQ → DELAY → LIMITER → MEASUREMENT → AI → SEND DSP
```
그래프 3색 오버레이 / AI 이유 설명 / A/B 비교는 이번 세션에서 **모바일에는 구현 완료**했지만,
Pro 앱은 완전히 다른 저장소(`/Users/howardchoi/Downloads/tunai_pro`)라 이번 세션에서 손대지
못했다. 다음 세션에서 그 저장소를 열고 동일한 3가지를 이식할 것.

---

## C. 특허

| 특허 | 상태 |
|---|---|
| SonicCore 청구항1 (CCV) | ✅ |
| SonicCore 청구항8 (해시매칭) | ✅ — COMMUNITY "내 스피커와 동일 규격" 필터 + LIBRARY에서도 재사용 |
| Closed Loop 청구항B-1 | ✅ |
| Modular Tuning Plate | ⏸ 미출원 — 외부공개 전 필수 |

## D. 하드웨어/서버

| 항목 | 상태 |
|---|---|
| ADAU1466 어댑터 | ✅ 구현완료 (PEQ/XO 주소 추정값) |
| 위상정합 Delay 블록 | ⏸ SigmaStudio 펌웨어 추가 필요 |
| 서버 소셜로그인 보안 | ✅ (.env에 GOOGLE/APPLE CLIENT_ID 입력 필요) |
| Firebase `aiTune` 함수 | ✅ 이번 세션에 soundScore/reason 추가 후 `asia-northeast3`에 배포 완료 |
| 출시 전 정리 | ⏸ 더미 프로파일/버튼 제거 |

---

# 이번 세션 완료 — TUNAI 모바일 전면 UX 재설계

## 핵심 철학
> "DSP를 조작하는 앱"이 아니라 "AI가 만든 결과를 확인하고 필요하면 미세 조정하는 앱"

## 진행 순서 — 전 항목 완료 (모바일 범위)

| # | 항목 | 상태 | 비고 |
|---|---|---|---|
| 1 | 탭 구조 변경 (CONNECT/MEASURE/AI/LISTEN/MORE) | ✅ | `lib/main.dart` RootScreen 5탭, IndexedStack |
| 2 | 상단 프리셋 바 (Factory/My Tune/AI Tune/Near Wall/Desk/Studio) | ✅ | `lib/shared/preset_bar.dart` |
| 3 | MEASURE — 위치 선택 (방이 Driver보다 먼저) | ✅ | `lib/core/install_location.dart`, `measure_screen.dart` |
| 4 | AI 화면 — Sound Score + 이유 설명 + 이유 태그 | ✅ | `ai_screen.dart` + `functions/index.js` (SYSTEM_MOBILE 프롬프트) |
| 5 | LISTEN — A/B 비교 + 3색 그래프 | ✅ | `spectrum_snapshot.dart`, `listen_screen.dart` |
| 6 | FINE TUNE — Warm/Neutral/Studio/Vocal/Movie/Bright | ✅ | `taste_preset.dart`, `fine_tune_screen.dart` |
| 7 | ADVANCED — PEQ/XO/Delay/Driver/보드선택 | ✅ | `advanced_screen.dart` (기존 home_screen.dart에서 이식) |
| 8 | LIBRARY 화면 | ✅ | `library_screen.dart` |
| 9 | COMMUNITY 강화 (별점/다운로드수/모델태그) | ✅ | `community_screen.dart` |
| 10 | APPLY 명칭 전체 통일 | ✅ | "SEND TO DSP"는 이미 없었음, "DSP에 적용"/"GET" → APPLY |
| 11 | Pro 그래프 오버레이 + AI 이유 설명 + A/B 비교 | ⏸ | **별도 저장소(tunai_pro) 필요 — 다음 세션** |

커밋: 5탭 골격/공유위젯 → home_screen 분해 → AI Sound Score → LISTEN → FINE TUNE →
프리셋 바 → LIBRARY → COMMUNITY 강화 → 명칭통일, 총 9개 커밋으로 분리. 매 커밋 `flutter analyze` 0 issues.

## 화면별 요약

- **CONNECT** (`lib/features/connect/connect_screen.dart`): BLE 스캔/연결만. 연결 성공 시 MEASURE로 자동 이동.
- **MEASURE** (`measure_screen.dart`): 위치 선택(desk/living_room/near_wall/studio/custom, `installLocationProvider`) →
  측정. 측정 완료 시 `spectrumSnapshotProvider`에 `before` 스냅샷 저장 + AI로 자동 이동.
- **AI** (`ai_screen.dart`): 측정 peaks + 선택된 위치를 `AiTuningService.suggest()`에 전달 (location 파라미터 신규).
  Sound Score 카드("AI says" 체크리스트), 밴드별 reason 태그, 트위터 보호 경고, APPLY. APPLY 성공 시
  `spectrumSnapshotProvider.applyPeaks()`로 `afterAi` 곡선 합성 + LISTEN으로 자동 이동. 최신 결과는
  `lastAiResultProvider`(`core/ai_tuning_service.dart`)에 저장돼 FINE TUNE/LIBRARY/프리셋바가 참조.
- **LISTEN** (`listen_screen.dart`): BEFORE/AFTER 토글(수동 + 0.5초 자동전환) + 회색(Before)/초록(After AI)/
  파랑(현재) 3색 오버레이. **주의**: `afterAi`는 실제 재측정이 아니라 before 곡선에 AI 밴드를 옥타브 단위
  가우시안으로 합성한 미리보기(`SpectrumSnapshotController._applyPeaksToBins`) — 실제 DSP 전송값에는 영향 없음.
- **FINE TUNE** (`fine_tune_screen.dart`, `taste_preset.dart`): 6종 취향 프리셋, 선택 시 LISTEN 파란선 즉시
  미리보기 갱신, APPLY 시 `lastAiResultProvider` 밴드 + 취향 밴드를 `maxPeqBands` 한도 내로 합쳐 전송.
- **ADVANCED** (`advanced_screen.dart`): 보드선택(TUNAI ONE/Isobarik/Reference) + T/S + FRD + 크로스오버 +
  채널 게인(기존 `home_screen.dart` 로직 그대로 이식) + 내 스피커 등록/COMMUNITY/HISTORY 진입점.
- **LIBRARY** (`library_screen.dart`): Factory Presets(=취향 6종), My Presets(AI Tune + My Tune, 저장일 표시),
  Community Best(상위 3개 + "내 스피커와 동일 규격" 필터).
- **MORE** (`more_screen.dart`): FINE TUNE/LIBRARY/ADVANCED/COMMUNITY/PROFILE 메뉴.

## 알려진 제약 (다음 세션 전 인지할 것)

- **Factory 프리셋 선택 = "무보정" 로컬 상태일 뿐, 하드웨어 진짜 초기화(bypass)는 아님.** 연결 중이면
  빈 패킷을 보내 실질적으로 아무 것도 전송하지 않는다. 진짜 팩토리 리셋이 필요하면 별도 구현 필요.
- **My Tune은 로컬 단일 슬롯**(SharedPreferences, `core/my_tune_storage.dart`). 클라우드 동기화·다중 슬롯은
  범위 밖 — 필요하면 COMMUNITY 업로드 플로우로 우회.
- **커뮤니티 별점은 좋아요 수 기반 근사치**(`_StarRating`, `community_screen.dart`). 전용 평점 API/DB 컬럼은
  없음 — 실제 별점 시스템을 원하면 서버 스키마 작업 필요.
- **LISTEN의 "After" 곡선은 예측 미리보기**(위 참고). 정확한 before/after 비교를 원하면 AI APPLY 후 실제
  재측정(MEASURE의 AUTO TUNE/Closed Loop)을 다시 돌려야 한다.

## 하지 않은 것 (이번 세션 범위 밖, 의도적으로 스킵)
- ADAU1466 주소 실측 — 별도
- 위상정합 펌웨어 — 별도
- 커뮤니티 판매 기능 — 별도
- Modular Tuning Plate — 별도

## 다음 세션 TODO
1. `/Users/howardchoi/Downloads/tunai_pro` 저장소를 열어 항목 11(그래프 3색 오버레이 + AI 이유 설명 +
   A/B 비교)을 Pro 앱에 동일하게 구현. `aiTunePro` 함수는 이미 `reason` 필드를 반환하므로 서버 쪽은
   추가 작업 없이 UI만 붙이면 됨.
2. 위 "알려진 제약" 중 우선순위가 생기는 항목부터 처리.

---

## 이번 세션 추가 — ADAU1701 PEQ/XO 주소 충돌 버그 수정 (`adau1701_adapter.dart`)

### 배경
`tunai_pro`의 adau1701_adapter.dart 작업(커밋 `0df8d39`) 중 동일 클래스의 버그를 모바일에서도 발견:
채널별 PEQ 베이스가 `peqBase + ch×30`(6밴드 가정)이었는데, 이는 `SystemProfile.maxPeqBands`(ADAU1701=10)와
어긋난 값이었고, 실제로 ch1의 PEQ 베이스(44)가 ch0의 XO 베이스(44)와 정확히 겹치는 주소 충돌이 있었다.

### 수정 내용
- **PEQ**: Gain/Mute와 동일하게 스테레오 링크 그룹(Woofer=ch0/1, Tweeter=ch2/3) 단위로 재구성.
  `peqBase=14`, 그룹당 10밴드×5계수=50워드 — Woofer그룹 14~63, Tweeter그룹 64~113 (20밴드 총합,
  `maxPeqBands=10`과 일치)
- **XO**: 근거 없이 PEQ 베이스에서 파생하던 식을 제거하고 미확정(`null`) 처리 — `writeCrossover`/
  `writeSubsonicFilter`는 SigmaStudio Filter 블록 주소 확인 전까지 no-op (Pro와 동일 패턴)
- Mute/Delay/Gain 로직은 변경 없음 (이번 스코프 아님), ADAU1466 어댑터도 변경 없음

### 확인
`flutter analyze` — 0 issues

### 커밋
`e67c7a7` — fix(mobile): ADAU1701 PEQ/XO 주소 충돌 버그 수정 (adau1701_adapter.dart)

---

## 이번 세션 추가 — ADAU1701 주소맵 전면 정정: PEQ→XO (`adau1701_adapter.dart`)

### 배경 (근거)
바로 위 세션에서 "PEQ는 스테레오 링크 그룹당 10밴드, 14~113"으로 정정했으나, 이 가정 자체가 틀렸음이
실제 SigmaStudio export 원본(`JAB4_DSP_Firmware_Hardware_SouceCode_V112_2021_01_12_IC_1_PARAM.h`)
대조로 확인됨. **이 펌웨어에는 PEQ 모듈이 아예 없다.** addr 14~799는 전부 크로스오버(XO)용 2차
필터 캐스케이드 8개(스테레오 페어 4쌍) + 210~211 믹서로 구성돼 있었다:

| 블록 | 주소 |
|---|---|
| Filter1_4 | 14~111 |
| Filter1_9 | 112~209 |
| 2XMixer1_3 (XO 믹스 포인트) | 210~211 |
| Filter1_10 | 212~309 |
| Filter1_11 | 310~407 |
| Filter1_5 | 408~505 |
| Filter1_8 | 506~603 |
| Filter1_6 | 604~701 |
| Filter1_7 | 702~799 |

참고용(미사용): SW vol1=800, Gain3/Gain1=801~804, Inv1_10/Inv1_9(극성)=810/811.
Vol(7)/Vol_2(6)/Mute0_2(11/12)/출력뮤트(805~808)는 기존과 일치 — 변경 없음.

### 수정 내용
- **PEQ 완전 제거**: `writeBiquad`는 이 펌웨어가 지원하지 않으므로 no-op으로 변경. 이전
  `peqBase=14` 가정은 실제로는 XO 캐스케이드 영역이었음(잘못 쓰면 크로스오버가 깨짐)
- **XO 8블록 구조 도입**: `_xoFilterBlockBase`(8개 확정 주소) + `_xoMixerBase`(210) 상수화.
  단, 블록 → (채널, HPF/LPF) 매핑과 블록 내부 스테이지 오프셋(98워드 안에서 계수가 몇 워드
  간격으로 배치되는지)은 아직 미확정 — `_xoBlockIndex()`가 `null`을 반환해 `writeCrossover`/
  `writeSubsonicFilter`는 그대로 no-op 유지. **Boot Camp Windows에서 SigmaStudio .dspproj를
  열어 각 블록의 실제 라벨(우퍼/트위터, LPF/HPF)을 육안 확인 후 반영 필요**
- **PEQ UI 주석 처리**: `system_profile.dart`의 `maxPeqBands`에 "이 하드웨어엔 PEQ가 없어 UI에서
  밴드를 편집해도 실기기에 전송 안 됨" 주석 추가 (UI 자체는 이번 스코프에서 손대지 않음)
- Mute(11/12, 805~808)/Vol(6/7)/Delay 로직은 변경 없음, ADAU1466 어댑터도 변경 없음

### 확인
`flutter analyze` — 0 issues

### 다음 세션 필수 선행 작업
Boot Camp Windows + SigmaStudio에서 `.dspproj` 열어 8개 필터 블록의 실제 라벨과 내부 스테이지
워드 레이아웃을 확인해야 XO 기능이 실제로 동작한다. 그 전까지는 크로스오버 조정 UI를 만져도
실기기에 아무 것도 전송되지 않는다(안전한 no-op).

### 커밋
`483ec8b` — fix(mobile): ADAU1701 주소맵 전면 정정 — PEQ 모듈 없음 확인, XO 8필터블록 구조 (adau1701_adapter.dart)

---

## 이번 세션 추가 — XO 블록 라벨/오프셋 확인 시도 (코드 변경 없음, 순수 조사)

### 배경
`writeCrossover`가 no-op인 이유(블록→채널/필터타입 매핑, 블록 내부 오프셋 미확정)를 풀기 위해
Boot Camp Windows + SigmaStudio에서 `.dspproj`를 열어 육안 확인하는 작업이 필요했음. 이 세션에서는
**내가 SigmaStudio GUI를 직접 조작할 수 없어 해당 확인을 완료하지 못했다** — Boot Camp/Windows
파티션이 현재 마운트돼 있지 않았고, 애초에 이 검증은 사람이 스키매틱을 눈으로 보고 신호 흐름을
따라가야 하는 작업이라 자동화가 불가능함.

### 그래도 확인한 것
`.dspproj` 원본 파일이 이미 이 Mac에 있다는 걸 확인함(OneDrive 동기화, Boot Camp 불필요):
`~/Downloads/SONIC CORE/WONDOM/ICP5/JAB4_DSP_ADAU1701_DemoProgram_V112_2021.01.12/
JAB4_DSP_Firmware_Hardware_SouceCode_V112_2021.01.12.dspproj`
(파일명 오타 주의: 폴더/zip은 `2021.01.12`, 파일 자체는 `SouceCode`.)

이 파일은 .NET BinaryFormatter 직렬화 바이너리라 텍스트 파싱으로는 셀 이름/클래스 타입 정도만
나오고, 필터 타입(LPF/HPF)이나 배선 연결 관계, 우퍼/트위터 라벨은 전혀 추출되지 않음(둘 다 GUID로
연결된 바이너리 오브젝트 그래프에 있음 — 스키매틱 캔버스에 사람이 붙인 텍스트 라벨이 없어서 더더욱
불가능). `strings`로 뽑아본 결과 확인된 것: 8개 필터 인스턴스명(`2nd Order Filter1_4`~`1_11`),
`2XMixer1_3`(`ADICtrls.TwoChannelXMixer`/`TwoChanXMixer1940Alg`), `Gain1940AlgNS`×5,
`MuteSWSlewAlg`×3, `Inv1_9`/`Inv1_10`, `SW vol 1`(`Gain3`), `AUX_ADC_0~3` — 전부 이미 알고 있던
정보의 재확인일 뿐, 새로운 매핑 정보는 없음.

### 다음 세션 필수 선행 작업 (변경 없음)
위 `.dspproj`를 Windows에서 SigmaStudio로 열어(Boot Camp 또는 Windows 머신), 8개 필터 블록을
클릭해서 실제 라벨/신호 흐름과 Link Compile Results의 IC Memory 표(파라미터명 순서)를 확인해야
한다. 대안으로, 실기기 상태에서 정품 Miumax 앱으로 크로스오버를 조정하며 BLE/UART 트래픽을
캡처하는 방법도 있음 — 어떤 주소에 어떤 값이 쓰이는지 실측으로 알 수 있어 어쩌면 더 확실할 수
있다(단, 캡처 인프라 구축 필요, 별도 세션 스코프).

### 코드 변경
없음 (순수 조사)

---

## 이번 세션 추가 — writeCrossover 실제 구현 (`adau1701_adapter.dart`)

### 배경
사용자가 SigmaStudio 스키매틱을 직접 확인(2026-07-04)해서 구조를 확정했음:
2웨이 크로스오버, 물리 DAC 4채널(각각 HPF 블록 → LPF 블록 캐스케이드):

| DAC | 역할 | HPF 블록 | LPF 블록 |
|---|---|---|---|
| DAC0 | Tweeter A | Filter1_4 (14~111) | Filter1_11 (310~407, @20kHz≈통과) |
| DAC1 | Tweeter B | Filter1_9 (112~209) | Filter1_10 (212~309, @20kHz≈통과) |
| DAC2 | Woofer A | Filter1_5 (408~505, @150Hz≈무시) | Filter1_6 (604~701) |
| DAC3 | Woofer B | Filter1_8 (506~603, @150Hz≈무시) | Filter1_7 (702~799) |

트위터 체인은 HPF가, 우퍼 체인은 LPF가 실질적 크로스오버 지점 — 반대쪽 블록은 스키매틱
기본값이 사실상 통과/무시로 설정돼 있을 뿐 실제 쓸 수 있는 필터임. 각 98워드 블록 내부의
정확한 스테이지 오프셋과 fixed-point 포맷은 아직 실측 검증되지 않음.

### 수정 내용
- `writeCrossover` 실제 구현: 채널(0/1=Woofer, 2/3=Tweeter) → 위 표 기반 (HPF 블록, LPF 블록)
  주소 매핑(`_xoBlockBase`) 후, 표준 크로스오버 biquad(Butterworth/LR, bw2~lr8) 계산해서 write.
  계수 순서는 SigmaStudio 표준(B2,B1,B0,A2,A1)으로 재배열 — 기존 (제거됐던) 구현은 b0,b1,b2,a1,a2
  순서였는데 이게 틀렸을 가능성이 있어 이번에 수정
- **안전장치**: `Adau1701Adapter.experimentalXoWriteEnabled` 정적 플래그, 기본 `false`. 블록 내부
  오프셋/계수 포맷이 실측 검증되지 않았기 때문에, 이 플래그가 꺼져 있으면 `writeCrossover`는
  계산만 하고 실제 전송은 하지 않음. UI 쪽 "실험적 기능 동의" 토글 연결은 이번 세션 스코프 밖 —
  상위 레이어에서 명시적으로 옵트인해야 함
- `writeSubsonicFilter`는 계속 no-op — 이 구조엔 별도 subsonic 개념이 없음(Woofer HPF 블록이
  유사한 역할을 할 수 있으나 오프셋/기본값 미검증이라 보류), 사유를 주석으로 남김
- `writeBiquad`(PEQ)/`writeDelay`는 계속 no-op — 각각 "Miumax UI엔 EQ/Delay가 보였으나 이
  스키매틱엔 없음, 별도 확인 필요"로 주석 갱신
- Mute/Vol/Gain/Inv 로직은 변경 없음

### 확인
`flutter analyze` — 0 issues

### 다음 세션 필수 선행 작업
`experimentalXoWriteEnabled=true`로 켜기 전에 반드시 이전 세션에서 설계한 BLE/UART 트래픽 캡처로
블록 내부 오프셋과 계수 포맷을 실측 검증할 것. 검증 없이 실기기에 쏘면 크로스오버가 의도와 다르게
동작하거나 무음/왜곡이 발생할 수 있음 — 실기기 테스트 시 반드시 낮은 볼륨에서 시작하고 이상 있으면
즉시 전원 차단.

### 커밋
`eec49cd` — feat(mobile): ADAU1701 writeCrossover 실제 구현 — 실험적 기능 플래그로 기본 OFF (adau1701_adapter.dart)

---

## 이번 세션 추가 — 신 펌웨어 반영: 표준 5워드 biquad (`adau1701_adapter.dart`)

### ⚠️ 실기기 테스트 전 필수 확인 사항
**이 세션의 주소맵은 SigmaStudio에서 필터 셀을 "General 2nd Order w var Param/Lookup/Slew"
(96워드 lookup)에서 표준 "General (2nd order)"(5워드 biquad)로 교체하고 재컴파일한 신
펌웨어 기준이다. 이 신 펌웨어가 아직 실기기(TUNAI ONE 보드)에 플래시되지 않았을 수 있다.**
`experimentalXoWriteEnabled`를 켠 채로 구 펌웨어가 올라간 보드에 연결하면 완전히 엉뚱한
주소에 값을 쓰게 된다. **실기기 테스트 전 반드시 SigmaStudio로 이 신 펌웨어를 보드에
플래시할 것.**

### 배경
실제 export .h 파일 기준으로 확정된 신 주소맵(필터 블록당 5워드, addr 16~55):

| 블록 | B0 | B1 | B2 | A0 | A1 | 역할 |
|---|---|---|---|---|---|---|
| GenFilter1   | 41 | 42 | 43 | 44 | 45 | Tweeter A HPF |
| GenFilter1_5 | 46 | 47 | 48 | 49 | 50 | Tweeter A LPF |
| GenFilter1_2 | 16 | 17 | 18 | 19 | 20 | Tweeter B HPF |
| GenFilter1_6 | 26 | 27 | 28 | 29 | 30 | Tweeter B LPF |
| GenFilter1_3 | 21 | 22 | 23 | 24 | 25 | Woofer A HPF |
| GenFilter1_7 | 31 | 32 | 33 | 34 | 35 | Woofer A LPF |
| GenFilter1_4 | 36 | 37 | 38 | 39 | 40 | Woofer B HPF |
| GenFilter1_8 | 51 | 52 | 53 | 54 | 55 | Woofer B LPF |

DAC 매핑: DAC0=Tweeter A, DAC1=Tweeter B, DAC2=Woofer A, DAC3=Woofer B.
다른 주소(Vol_2=6, Vol=7, Mute0_2 on/off=11/step=12, Mute1=805~806, Mute0=807~808,
Inv=810~811, I2C=0x34)는 변경 없음.

### 중요 발견 — 슬로프 제한
이전 펌웨어는 채널당 98워드 cascade라 여러 biquad를 이어붙일 수 있다고 가정했었지만,
신 펌웨어는 **필터 블록당 정확히 5워드(2차 biquad 1스테이지)뿐이다.** 즉 bw4/lr4/lr8처럼
2스테이지 이상을 요구하는 슬로프(24dB/oct 이상)는 이 하드웨어로 구현이 불가능하다.
지원 가능한 최대는 bw2/lr2(12dB/oct, 1스테이지)뿐 — `writeCrossover`는 슬로프가 2스테이지
이상을 요구하면 얕은(잘못된) 응답을 보내는 대신 아무 것도 쓰지 않도록 구현했다.

### 수정 내용
- 필터 주소 상수/매핑을 위 표대로 전면 재작성 (기존 addr 14~799, 98워드/블록 → addr 16~55,
  5워드/블록)
- 계수 write 순서를 B0,B1,B2,A0,A1로 정정 — SigmaStudio "General 2nd order filter"의
  A0/A1은 우리 내부 표기의 a1/a2와 동일한 자리(0-index 명명 차이일 뿐)라서, 내부
  `_BQ(b0,b1,b2,a1,a2)`를 재배열 없이 그대로 write하면 됨. 이전 세션의 B2,B1,B0,A2,A1
  가정은 틀렸었음(구 96워드 lookup 필터 기준으로 추정한 값)
- `experimentalXoWriteEnabled` 기본값을 `true`로 전환 — 신 주소/포맷이 실측 export .h
  기준으로 확정됐다고 판단
- Fixed-point는 ADAU1701 표준 5.23 가정 유지(이번 세션에서 재확인은 안 됨)
- `writeBiquad`(PEQ)/`writeDelay`는 계속 no-op(이 신 펌웨어에도 PEQ/Delay 모듈 없음),
  `writeSubsonicFilter`도 계속 no-op(subsonic 개념 없음)
- Mute/Vol/Gain/Inv 로직 변경 없음

### 확인
`flutter analyze` — 0 issues

### 다음 세션
1. **신 펌웨어를 실기기에 플래시** (SigmaStudio, .dspproj → Link Compile → Write Latest
   Compilation to E2PROM 등)
2. 저볼륨으로 앱에서 크로스오버 슬라이더 조작 → 실제 필터 반응 확인
3. 이상 있으면 즉시 전원 차단, `experimentalXoWriteEnabled`를 다시 `false`로

### 커밋
`c28c160` — feat(mobile): ADAU1701 신 펌웨어 반영 — 표준 5워드 biquad, writeCrossover 활성화 (adau1701_adapter.dart)

---

## 이번 세션 추가 — ADAU1466 주소 전면 반영 (`adau1466_adapter.dart`)

### 배경
`1466_cs42448_18out_eng` 실제 export 대조로 확정된 주소맵 반영. Volume은 기존 검증값과
일치(변경 없음), Delay/PEQ는 신규 확정, HPF/LPF는 구조 자체가 PEQ/Delay와 다르다는 게
새로 발견됨(SafeLoad 방식).

- **Delay** (신규 확정): ch0~5 = 562, 567, 563, 566, 564, 565 — 채널 순서는 Volume과
  동일 CH0~5로 가정(실기기에서 채널별 소리로 확인 필요)
- **PEQ** (신규 확정, 15밴드): base=410, 밴드n(0~14)=410+n×5, addr 410~484. 계수 순서
  B2,B1,B0,A2,A1(ADAU1701 신 펌웨어의 B0,B1,B2,A0,A1과 다름). **채널별 스트라이드는
  이번 export에 없어서, 현재 모든 채널이 410 기준 단일 15밴드를 공유하는 것으로
  구현했다** — 채널별 개별 PEQ가 필요하면 추가 확인 필요
- **HPF/LPF 크로스오버** (신규 발견, 구조 다름): HPF target=24873~24877(slewMode=401),
  LPF target=24878~24882(slewMode=407). SafeLoad 레지스터 영역(24576~24583)과 인접 —
  일반 write가 아니라 SigmaStudio SafeLoad 프로토콜(데이터→ADDRESS→NUM 순서로 써서
  트리거) 필요할 가능성이 높음. **불확실 — 표준 ADI SafeLoad 레지스터 배치를 가정한
  스텁만 작성**하고 `experimentalXoWriteEnabled=false`로 잠금(1701과 동일 패턴)
- Mute 16채널(1081~1096), Compressor(489~542, 범위만) 참고용으로 클래스 doc에 추가
- Volume 로직/주소는 변경 없음

### 확인
`flutter analyze` — 0 issues

### 다음 세션
1. 실기기에서 PEQ/Delay 저볼륨 테스트 — Delay는 채널 순서(562,567,563,566,564,565)가
   실제로 CH0~5와 맞는지 소리로 확인
2. XO(HPF/LPF)는 SafeLoad 프로토콜 자체를 조사(ADI 문서 또는 실측 캡처)한 뒤에만
   `experimentalXoWriteEnabled`를 켤 것 — 지금 스텁은 레지스터 배치를 가정한 것일 뿐
   검증되지 않음

### 커밋
`2281717` — feat(mobile): ADAU1466 주소 전면 반영 — PEQ/Delay 확정, XO는 SafeLoad 구조 (adau1466_adapter.dart)

---

## 이번 세션 추가 — 모바일 UX 개선 1단계: 문구/표시 개선 (GPT UX 리뷰 반영)

### 배경
GPT UX 리뷰 제안 중 코드 영향이 적은 것부터 진행. Pro는 이번 스코프 아님, DSP 로직/주소
변경 없음 — 순수 UI 레이어만.

### 수정 내용
1. **버튼 라벨**: `measure_screen.dart`의 "AUTO TUNE (반복수렴)" → "AI Optimize (반복수렴)"
   (기능/로직 동일, 라벨만)
2. **Sound Score 개선폭 표시**: `ai_screen.dart`의 `_AiTunePanelState`에 `_previousScore`
   필드 추가 — `_suggest()` 재호출 시 이전 `_result.soundScore`를 캡처해 넘겨줌.
   `_SoundScoreCard`가 이전 점수가 있으면 "89 → 96 (+7)" 형식(색상: 상승 초록/하락 빨강),
   없으면 기존처럼 단일 숫자만 표시. 시스템 프로파일 전환 시 `_previousScore`도 함께 리셋
3. **"AI says" 수치 포함**: `_SoundScoreCard`의 reason 목록을 밴드별 `frequency`/`gainDb`와
   묶어 "책상 반사로 인한 피크 보정 — 180Hz, -3.2dB" 형식으로 표시. **백엔드 확인 결과
   `functions/index.js`의 `aiTune` 응답이 이미 밴드마다 `frequency`/`gainDb`/`reason`을
   별도 필드로 반환하고 있어(SYSTEM_MOBILE 프롬프트 스키마 기준) 백엔드 수정은 불필요했음**
   — 클라이언트에서 이미 있는 필드를 조합해서 표시만 개선
4. **프리셋 바에 "Reference" 추가**: `preset_bar_provider.dart`의 `PresetBarSelection`
   enum에 `reference` 추가, 순서를 Factory/Reference/AI Tune/My Tune/(배치 프리셋)으로
   재배열. **Factory와 동일하게 플랫 EQ(무보정)로 정의**(Dart 표준 라이브러리 상
   `peaks = const []`) — 실제로 구분되는 기준 커브 데이터가 없어서 1단계에서는 이름만
   분리. 향후 진짜 "기준 커브"(예: 공장 측정 원본 곡선) 데이터가 생기면 그때 로직을
   분리할 것. `preset_bar.dart`의 `_select()` switch에 `case reference` 추가(exhaustive
   switch라 빠뜨리면 컴파일 에러 — 안전)

### 확인
`flutter analyze` — 0 issues. **UI 실측 테스트는 못 함** — AI 튜닝 결과 표시는 실제
측정 데이터+Firebase 응답이 있어야 확인 가능해서 코드 리뷰 수준으로만 검증했음. 다음
세션에서 실기기/시뮬레이터로 AI 탭 플로우를 한번 돌려 Sound Score 델타 표시와 "AI says"
문구가 의도대로 나오는지 확인 필요

### 다음 세션
1. 위 4개 변경사항 실제 화면에서 시각 확인
2. 2단계(CONNECT 플로우 개선) 착수 여부 확인

### 커밋
`dd48ab8` — feat(mobile): UX 개선 1단계 — 문구/표시 개선 (GPT 리뷰 반영)

---

## 이번 세션 추가 — 모바일 UX 개선 2단계: CONNECT 플로우 개선 (GPT UX 리뷰 반영)

### 배경
1단계(문구/표시)에 이어 CONNECT 화면 플로우 확장. Pro는 이번 스코프 아님, BLE 스캔/연결
핵심 로직(`ble_controller.dart`의 실제 스캔/연결 호출)은 변경 없음 — 상태 세분화 +
UI 레이어만.

### 수정 내용
1. **단계별 진행상태 체크리스트**: `BleConnectionState`에 `found`(스캔 중 기기 발견 순간)와
   `notFound`(스캔 완료 후 못 찾음, 기존엔 `error`로 뭉쳐 있었음) 두 상태를 세분화 추가.
   실제 스캔 루프(`scanAndConnect`)는 그대로 두고, 기기를 찾은 시점에 `found` 상태를 잠깐
   거쳐가도록 한 줄만 추가. `connect_screen.dart`에 새 `_ConnectSteps` 위젯 — Bluetooth
   ON/Speaker Found/Connecting.../Connected 4단계를 체크마크(✓)로 표시, 진행 중인 단계는
   스피너로 표시
2. **연결 완료 확장 화면**: 새 `_ConnectedInfoCard` — 기기 아이콘+이름, "Ready" 상태,
   "Start AI Setup" 버튼(MEASURE 탭 이동, 기존 `onConnected` 콜백 재사용). **Firmware
   버전은 생략** — `fff1`(NOTIFY 특성)이 코드에 정의만 돼 있고 실제로 read/subscribe하는
   경로가 없어서, 페이로드 포맷이 확인되기 전까지는 표시하지 않기로 함(추후 별도 작업)
3. **최초 실행 웰컴**: 새 `lib/core/onboarding_storage.dart`(SharedPreferences, `MyTuneStorage`
   패턴 따름) — "Welcome to TUNAI — Let's make your speaker sound amazing." 다이얼로그를
   `ConnectScreen`(이제 `ConsumerStatefulWidget`으로 전환) `initState`에서 1회만 표시
4. **검색 실패 가이드**: 새 `notFound` 상태일 때 `_ScanFailureGuide` 카드 — "Can't find your
   speaker?" + Turn on speaker/Move closer 안내 문구, "Setup New Speaker" 버튼은 재스캔
   (`scanAndConnect()` 재호출)으로 연결 — 별도 페어링 관리 기능은 없어서 정직하게 재시도로 매핑
5. **MEASURE 진입 전 체크리스트**: 새 `preMeasureChecklistDoneProvider`(세션 동안만 유지,
   앱 재시작 시 리셋)와 `_PreMeasureChecklist` 위젯 — Microphone/Speaker Ready, Environment
   Quiet 3항목. **체크 여부와 무관하게 "확인" 버튼은 항상 활성** — 강제 검증이 아닌 안내용 UI

### 확인
`flutter analyze` — 0 issues. **UI 실측 테스트는 못 함** — 실제 BLE 기기 연결/해제
사이클과 최초 실행 상태를 시뮬레이터에서 재현하려면 별도 준비가 필요해서 코드 리뷰
수준으로만 검증했음

### 다음 세션
1. 실기기로 CONNECT 전체 플로우(스캔→발견→연결→Ready 화면, 못 찾았을 때 가이드, 앱
   최초 실행 웰컴, MEASURE 체크리스트) 한번 돌려 확인
2. 3단계(LISTEN Loop, Speaker Health, Test Tone) 착수 여부 확인
3. Firmware 버전 표시가 필요하면 `fff1` 특성의 실제 페이로드 포맷부터 확인(SigmaStudio
   또는 실기기 BLE 덤프)

### 커밋
`bf15464` — feat(mobile): UX 개선 2단계 — CONNECT 플로우 개선 (GPT 리뷰 반영)

---

## 이번 세션 추가 — 모바일 UX 개선 3단계(최종): LISTEN Loop / Test Tone / Speaker Health

### 배경
1단계(dd48ab8)·2단계(bf15464)에 이어 GPT UX 리뷰 마지막 단계. BLE/DSP 핵심 통신
로직은 변경 없음. **중요 발견**: LISTEN 화면은 애초에 실제 오디오를 재생하는 화면이
아니라 Before/After 스펙트럼 "그래프"를 토글하는 화면이었다(기존에도 오디오 재생
코드가 전혀 없었음) — 이 사실을 확인하고 "Loop"를 실제 오디오 A/B가 아니라 기존
그래프 자동전환 기능의 명칭/주기 변경으로 정직하게 구현했다(가짜로 오디오가 재생되는
것처럼 보이게 하지 않음).

### 수정 내용
1. **LISTEN Loop**: 기존 "0.5s" 자동전환 칩을 "LOOP"로 개명하고 주기를 1.5초로 변경
   (`_autoSwitch`→`_loop`, `500ms`→`1500ms`). **탭 이탈 시 자동 정지** 요구사항을 위해
   `main.dart`에 `currentTabIndexProvider`(새 StateProvider) 추가 — `IndexedStack`은
   비활성 탭을 dispose하지 않아 기존 `dispose()`만으로는 탭 전환 시 타이머가 안 멈췄던
   문제를 해결. `RootScreen`을 `ConsumerStatefulWidget`으로 전환해 `_goTo()`에서 이
   provider를 갱신, `ListenScreen`이 `ref.listen`으로 감지해 LISTEN(index 3)을 벗어나면
   `_setLoop(false)` 호출
2. **Test Tone 확인**: 새 `lib/core/tone_generator.dart`(`PinkNoiseGenerator`와 동일한
   WAV 헤더 구조, 파형만 1kHz 사인파로 교체, 클릭음 방지용 10ms 페이드인/아웃 포함).
   `connect_screen.dart`에 `_TestToneDialog` 추가 — 연결 성공 시 `widget.onConnected()`를
   바로 부르지 않고 이 다이얼로그를 먼저 띄움: 1초 재생 → "들리나요?" YES/NO.
   YES면 MEASURE로 진행. NO면 트러블슈팅 안내(볼륨/케이블/입력소스 확인) + "다시 시도"
   버튼. 완전히 막히는 걸 방지하기 위해 트러블슈팅 화면에 "건너뛰기"도 추가(스펙엔 없었지만
   재생이 정말 안 되는 환경—예: 개발 중 스피커 미연결—에서 못 빠져나가는 걸 막기 위한 판단)
3. **Speaker Health 신규 화면**: `lib/features/health/speaker_health_screen.dart`,
   MORE 메뉴에 항목 추가. **DSP Load/Amplifier/Tweeter/Woofer/Limiter 전부 "정보 없음"
   으로 표시** — `DspAdapter.readCurrentState()`가 두 어댑터(1701/1466) 모두 항상
   `DspState(raw: {})` 빈 값을 반환하고, BLE `fff1`(NOTIFY 특성)은 상수로 정의만
   돼 있을 뿐 실제 subscribe/read 코드가 전혀 없음을 확인했음(grep으로 `setNotifyValue`/
   `lastValueStream` 전무 확인). 화면 상단에 "하드웨어 지원 준비중" 배지 고정 표시 —
   2단계에서 Firmware 버전을 생략한 것과 동일한 원칙(가짜 데이터 절대 금지)

### 확인
`flutter analyze` — 0 issues. **UI 실측 테스트는 못 함** — Test Tone은 실제 오디오
출력 장치+연결된 스피커가 있어야 의미 있게 확인 가능하고, LISTEN Loop 탭 이탈 정지는
실기기/시뮬레이터로 탭을 오가며 확인해야 해서 코드 리뷰 수준으로만 검증했음

### GPT UX 리뷰 3단계 전체 완료
1단계(dd48ab8, 문구/표시) → 2단계(bf15464, CONNECT 플로우) → 3단계(이번 커밋, LISTEN
Loop/Test Tone/Speaker Health)까지 모두 반영 완료. 다음은 실기기 테스트 순서.

### 커밋
`ef909fc` — feat(mobile): UX 개선 3단계(최종) — LISTEN Loop, Test Tone, Speaker Health (GPT 리뷰 반영)

---

## "Living Speaker" 아키텍처 브리프 — Gap Analysis (진단 전용, 코드 변경 없음, 2026-07-04)

### 배경
새 5계층 아키텍처 브리프(AIP/AOS/AIE/AKG/ACM) 도착. 현재 tunai/tunai_pro 코드베이스가
이 구조와 얼마나 부합하는지 순수 진단만 수행 — 리팩토링/신규 구현 없음.

### 5계층 매핑

| 계층 | 매핑된 모듈 | 상태 | 격차 |
|---|---|---|---|
| **AIP** (플랫폼) | Firebase(Analytics/Crashlytics/Functions만, Firestore 미사용·패키지도 없음) + 별도 커스텀 REST API(`api.tunai.kr`, `lib/core/api_service.dart`) — auth/device 등록/community/measurement 업로드. `my_tune_storage.dart`는 로컬(SharedPreferences)만 | 부분있음 | Firebase와 REST API가 서로 분리된 두 시스템, 로컬↔클라우드 동기화 없음(My Tune은 아예 클라우드 대응 없음), 통합 플랫폼 데이터 레이어 없음. tunai_pro는 Firebase 의존성 자체가 없음 |
| **AOS** (운영체제) | `dsp_controller.dart`(Pro, 프리셋 저장/로드 CRUD), `preset_bar_provider.dart`+`preset_bar.dart`(모바일, Factory/Reference/AI Tune/My Tune 선택) | 부분있음(보호 로직 없음) | 상태머신이 아니라 단순 CRUD(전이 가드 없음). Factory/User 레이어 분리 없음. 트위터 보호 클램프 전무 — `SafetyProfile.clampBassBoost`(우퍼<200Hz 전용)만 존재하고 그마저 측정 후 1회성 자동튠에만 호출됨 |
| **AIE** (지능엔진) | `functions/index.js`의 `aiTune`/`aiTunePro`, `ai_tuning_service.dart`, Sound Score(LLM 자체 산출) | 부분있음 | 타겟커브 개념 코드에 없음(grep 0건). 후보 여러개 생성 안 함(LLM 1회 호출→1개 결과 그대로 사용). 프롬프트에 "flat화 지양"/"dip 과잉boost 금지" 지시 없음. 서버측 스키마/범위 검증 없음(LLM JSON 출력 그대로 클라이언트 전달) |
| **AKG** (지식그래프) | `speaker_profile.dart`, `install_location.dart`, `spectrum_snapshot.dart`, `taste_preset.dart`, community의 `enclosure_hash` | 거의 없음 | 모든 엔티티가 독립된 flat 구조/전역 Riverpod provider로 존재 — `deviceId`/`profileId`/`locationId` 등으로 서로 연결되는 코드 0건(전수 grep 확인). 유일한 연결점은 `enclosure_hash`(스피커 인클로저 지오메트리에서 파생한 약한 지문, preset↔enclosure만 연결) — 기기/측정/튜닝/선호를 잇는 진짜 관계형·그래프 모델은 없음 |
| **ACM** (실행계층) | `dsp_adapter.dart` 인터페이스 + `adau1701_adapter.dart`/`adau1466_adapter.dart`(mobile+Pro 각자), `ble_controller.dart`(모바일)/`connect_controller.dart`(Pro, UART+BLE) | 있음(단, 중복) | 인터페이스 자체는 깔끔히 분리(칩별 주소/픽스드포인트 로직이 어댑터 밖으로 새지 않음, 확인됨). 단 tunai/tunai_pro가 완전히 독립된 복사본 — 공유 패키지 없어 이미 `RawWriteFn` 시그니처가 서로 다름(모바일 `Future<bool> Function(List<int>)` vs Pro `Future<void> Function(Uint8List)`), drift 위험 |

### "MVP에서도 반드시 남겨야 할 구조" 8개 항목 체크

| # | 항목 | 상태 | 위치 | 격차 |
|---|---|---|---|---|
| A | Tuning Package abstraction | 부분있음 | `dsp_controller.dart`(Pro) `DspState` 저장/로드(131~163행) — gain/delay/PEQ/XO 모두 포함; `my_tune_storage.dart`(모바일) | 모바일 My Tune은 PEQ 밴드만 저장(XO/Delay 없음). 두 repo가 공유하는 번들 모델 없음 |
| B | DSP Platform abstraction | **있음** | `dsp_adapter.dart`(양쪽 repo) | ACM 항목 참고 — 확인됨, 격차 없음 |
| C | Factory / User Layer separation | **없음** | `preset_bar.dart:36-38`(Factory = `const []` 하드코딩), `dsp_controller.dart:131-163`(모든 프리셋이 같은 `dsp_presets`/`dsp_preset_$name` 네임스페이스) | "Factory"라는 이름의 프리셋도 사용자가 그대로 덮어쓰기/삭제 가능 — read-only 플래그나 보호된 네임스페이스가 아예 없음 |
| D | Safety Validation Layer | **부분있음(실질적으로 핵심 경로엔 없음)** | `ai_screen.dart:_applyAll`, `preset_bar.dart:_select`, `dsp_controller.dart:updateOutputBand/updateOutputGain` | 개별 슬라이더 편집 다이얼로그엔 범위 제한(freq/gain/Q)이 있지만, **실제 BLE/UART로 나가는 3개 경로(AI 일괄적용, 프리셋 전환, PEQ 밴드 저장)엔 클램프가 전혀 없음.** 트위터 채널 특정 보호는 0건(아래 안전원칙 점검 참고) |
| E | Measurement History | **없음** | `spectrum_snapshot.dart`(before/afterAi/current 3슬롯짜리 전역 상태, 앱 재시작 시 소실) | 시계열 이력 없음. `api_service.dart`에 업로드 엔드포인트(`saveMeasurement`)는 있으나 조회/이력 UI가 어디에도 없음 |
| F | Target Curve Versioning | **없음** | (전수 grep 결과 0건: `targetCurve`/`target curve`/`reference curve`) | 타겟커브 개념 자체가 코드에 없음. AI는 매번 원시 peaks에서 처음부터 새로 제안만 함 |
| G | Preset and Rollback Structure | 부분있음 | `dsp_controller.dart` 저장/로드, `MyTuneStorage` | 여러 프리셋 저장/전환은 가능하나 undo/rollback(변경 직전 자동 스냅샷) 메커니즘은 없음. `preset_bar.dart:_save`도 기존 My Tune을 확인 없이 그냥 덮어씀 |
| H | AIP-ready Profile Model | **없음** | `SpeakerProfile`/`InstallLocation`/`SpectrumSnapshot`/`TastePreset`/`DeviceService`(`registered_device` 키)/`AuthController`(`user_id` 등 키) 전부 독립 | 통합 프로필 모델이 없고, 클라우드 확장 스키마로 쓸 단일 구조가 없음 — AKG 항목과 동일한 근본 원인 |

### 핵심 안전원칙 점검

**① 트위터 보호 필터가 사용자 EQ로 절대 우회 안 되는 구조인가 → 아니오, 사실상 보호 장치가 없음.**

실제 write-path 추적 결과(에이전트가 파일:라인 단위로 확인):
- **Pro 수동 슬라이더**: `peq_band.dart`의 게인 슬라이더(-24~24dB, 트위터/우퍼 동일 위젯) → `dsp_controller.dart:updateOutputBand`(클램프 없음, PeqBand 그대로 저장) → `sendToDsp()` → `Adau1701Adapter.writeBiquad`(현재 PEQ가 이 펌웨어에 없어 no-op — 다른 이유로 안 나감) / `writeGain`(클램프 없음) → `ConnectController.sendBytes`(값 검증 전혀 없이 raw bytes 전송)
- **모바일 AI 일괄적용**: `ai_screen.dart:_applyAll`(클램프 없음) → `DspCompiler.compileAll` → `toFixed523`의 클램프(`-16.0~15.9999999`)는 fixed-point 오버플로 방지용일 뿐 dB 세이프티가 아님 → `ble_controller.dart:sendPackets`(값 검증 없음)
- **유일한 실제 안전 클램프**: `SafetyProfile.clampBassBoost`(양쪽 repo에 중복 존재) — **우퍼(<200Hz) 전용**이고, 그마저 측정 후 1회성 자동튠 경로(`measurement_controller.dart:305-312`)에서만 호출됨. 수동 슬라이더/AI 일괄적용/프리셋 전환에는 전혀 안 걸림
- 트위터 보호는 **UI 경고 문구로만 존재**(`ai_screen.dart:266-267`, `measurement_mic_screen.dart:388-389` — "트위터 채널 게인을 크게 올리지 마세요") — 이 문구를 어떤 검증/차단 로직에도 연결하지 않음. 사용자가 무시하면 그대로 전송됨

**② Factory preset이 실제로 보호(읽기전용)되는가 → 아니오.**
모바일에서 Factory는 저장된 오브젝트가 아니라 하드코딩된 빈 배열(`const []`)일 뿐이라 "덮어쓸 대상" 자체가 없음(그 자체로는 안전하지만, 진짜 공장 캘리브레이션 데이터를 나타내지 않는다는 기존에 알려진 제약과 동일 선상). Pro는 프리셋을 이름 기반으로 저장하는데(`dsp_presets` 리스트 + `dsp_preset_$name`), "Factory"라는 이름이 특별 취급되지 않아 사용자가 그 이름으로 저장하면 덮어써짐.

### 종합 판단
현재 코드베이스는 **ACM(실행계층)과 AIE(지능엔진 프로토타입)는 실질적으로 존재**하지만, **AOS의 보호/롤백 구조, AKG의 관계형 데이터, AIP의 통합 플랫폼 레이어는 거의 없다.** 가장 시급한 격차는 **D(Safety Validation Layer)**와 **C(Factory/User 분리)** — 둘 다 "트위터 보호"라는 제품의 핵심 안전 약속이 현재 코드상 UI 문구 수준에 그친다는 같은 근본 문제를 가리킨다.

### 다음 세션
이 보고서를 바탕으로 어느 격차부터 메울지 논의 필요. (에이전트 권고 아님 — 사용자 판단 필요, 후보만 나열)
- 안전 최우선이면: D(Safety Validation Layer, 특히 트위터 클램프)부터
- 제품 신뢰성이면: C(Factory/User 레이어 분리)부터
- 장기 확장성이면: H/AKG(통합 프로필 모델)부터 — 다른 항목들이 이 위에 자연히 얹힘

### 커밋
`03bbc35` — docs(mobile): "Living Speaker" 아키텍처 브리프 기준 gap analysis (진단만, 코드 변경 없음)

---

## Safety Validation Layer 구현 완료 (AOS 항목 D, 2026-07-05)

### 배경
직전 gap analysis에서 확인된 핵심 문제: 트위터 보호가 UI 경고 문구로만 존재하고
실제 값 검증이 없었음. 이번 세션에서 mobile+Pro 동일 구조로 구현.

### 구현 중 발견한 추가 문제 (계획보다 스코프가 커진 이유)
1. **mobile의 AI 일괄적용/프리셋 전환은 애초에 `DspAdapter`를 거치지 않는다** —
   `ai_screen.dart:_applyAll`과 `preset_bar.dart:_select` 둘 다 `DspCompiler.compileAll()`
   →`RegisterPacket`→`bleProvider.sendPackets()`라는 완전히 별개의 레거시 파이프라인을
   쓴다(채널 개념 자체가 없고, 하드코딩된 `peqStartPramAddr=0x0010`부터 순차 배치).
   `DspAdapter`만 감싸는 걸로는 이 두 경로가 전혀 보호되지 않아서, `compileAll` 내부에도
   직접 검증을 넣어야 했음
2. **Pro의 `dsp_controller.dart:175`가 `profile.adapterFactory`를 거치지 않고
   `Adau1701Adapter`를 직접 생성**하고 있었음 — 이게 Pro의 실제 유일한 하드웨어 전송
   경로(`sendToDsp()`, 슬라이더/AI/프리셋 3개 진입점이 전부 여기로 모임)라서 발견하지
   못했다면 새 SafetyValidator를 완전히 우회하는 구멍이 됐을 것

### 수정 내용

**공통 (mobile+Pro 각자 파일 복제 구현 — ACM 계층처럼 공유 패키지가 없어서):**
- `lib/core/dsp_safety.dart` (신규) — `DspSafety` 클래스:
  - `validateChannelGain(gainDb, isTweeter)` — 트위터 채널 브로드밴드 게인 +6dB 상한
  - `validateCrossoverFreq(freqHz, side, isTweeter)` — 트위터 HPF 최소 1500Hz 강제
  - `validateBandGain(freqHz, gainDb, {maxBassBoostDb})` — 주파수+게인 기반 공용 검증.
    2kHz 이상 부스트는 트위터 상한(+6dB), 200Hz 이하 부스트는 저역 상한(기본 +6dB,
    드라이버별 Xmax 값을 안다면 `maxBassBoostDb`로 대체 가능) — 기존
    `SafetyProfile.clampBassBoost`(Xmax 기반)와 같은 취지의 저역 보호를 채널 정보 없는
    경로에서도 동작하도록 일반화
  - `validateBiquad(coeffs)` — biquad 계수만 주어졌을 때(원본 freq/gainDb가 없는
    `writeBiquad` 호출 시점) 20Hz~20kHz 로그 스윕으로 피크 게인/주파수를 역산해
    `validateBandGain`으로 위임. 위반 시 부분 재조정이 아니라 **passthrough로 전체
    무효화**(1차 구현, 보수적 — 정교한 재조정은 향후 개선 여지)
- `lib/core/dsp_safety_notice.dart` (신규) — `DspSafetyNotice`: 전역
  `GlobalKey<ScaffoldMessengerState>`로 어디서든(어댑터, 정적 함수 등 BuildContext
  없는 코드 포함) 스낵바를 띄움. `MaterialApp(scaffoldMessengerKey: ...)`에 연결
- `lib/core/dsp/validating_dsp_adapter.dart` (신규) — `ValidatingDspAdapter implements
  DspAdapter`: 내부 어댑터를 감싸 `writeGain`/`writeCrossover`/`writeBiquad` 호출마다
  `DspSafety`로 검증 후 위반 시 `DspSafetyNotice.show()`로 알리고 clamp된 값으로 전달.
  `writeDelay`/`writeSubsonicFilter`는 트위터/저역 보호와 무관해 그대로 통과
- `system_profile.dart`: 3개 프로파일의 `adapterFactory`가 항상
  `ValidatingDspAdapter(...)`로 감싼 인스턴스만 반환하도록 수정. 채널 리스트를
  top-level const로 추출해 `adapterFactory` 클로저와 `channels` 필드가 같은 리스트를
  참조(트위터 여부는 `ChannelConfig.type == ChannelType.tweeter`로 판별)

**mobile 전용:**
- `dsp_compiler.dart`의 `compileAll()` 내부에서 각 `ResonancePeak`를
  `DspSafety.validateBandGain`으로 검증 — 이 함수를 거치는 모든 호출자(`ai_screen`,
  `preset_bar`, `measurement_controller`, `fine_tune_screen`, `library_screen`,
  `community_screen` — grep으로 전수 확인)가 자동으로 보호됨

**Pro 전용:**
- `dsp_controller.dart:sendToDsp()`가 `Adau1701Adapter` 직접 생성 대신
  `profile.adapterFactory(rawWrite)` 사용하도록 수정 (위 "발견한 추가 문제 2" 해결)
- 부수 발견: Pro의 `SafetyProfile.clampBassBoost`는 정의만 돼 있고 **어디서도 호출되지
  않는 죽은 코드**였음(mobile은 `measurement_controller.dart`에서 실제로 호출함) — 이번에
  추가한 `DspSafety`가 Pro에서는 사실상 유일하게 동작하는 저역 보호임

### 우회 불가능한 구조인지 스스로 검증한 근거
1. `grep -rn "Adau1701Adapter(\|Adau1466Adapter("` 결과, 두 repo 모두 **`system_profile.dart`의
   `adapterFactory` 클로저 안에서만** 두 어댑터를 직접 생성함(수정 후 기준) — 다른 어떤 파일도
   두 클래스를 직접 `new`하지 않음
2. Pro의 유일한 예외였던 `dsp_controller.dart:175`를 `adapterFactory` 경유로 수정 완료(위 참고)
3. mobile의 `DspAdapter`를 완전히 우회하는 레거시 경로(`compileAll`)는 함수 내부 자체에
   검증을 심어서, 이 함수를 호출하는 방법 자체가 안전한 값만 내보내게 만듦 — 호출자가
   검증을 "깜빡하고 안 부르는" 실수가 원천적으로 불가능
4. `grep -rn "sendPackets(\|sendRawFrame(\|buildBleFrame(\|RegisterPacket("`로 두 repo의
   모든 실제 바이트 전송 지점을 확인 — `compileAll`을 거치거나(mobile) `DspAdapter`
   구현체 내부(양쪽 어댑터 파일 자체)뿐, 그 외 제3의 경로 없음
5. 위반 시 `DspSafetyNotice.show()`가 무조건 호출되므로(각 `validate*` 결과의
   `wasClamped`를 어댑터/컴파일러가 빠짐없이 체크) 조용히 값만 바뀌는 경우는 없음

### Do not 준수
- Factory/User 분리(C), AKG 프로필 모델(H)은 손대지 않음
- 기존 UI 경고 문구(`ai_screen.dart:266-267`)는 그대로 둠 — 이제 실제 로직과 별개로
  존재하는 "사전 안내"이고, clamp 발생 시엔 `DspSafetyNotice`가 "사후 확인"으로 추가됨

### 확인
`flutter analyze` — 0 issues. **실기기/UI 실측 테스트는 못 함** — 스낵바가 실제로
뜨는지, clamp된 값이 실제로 소리에 반영되는지는 시뮬레이터/실기기로 직접 트리거해봐야
확인 가능해서 코드 리뷰 수준으로만 검증했음

### 알려진 한계 (다음 세션 후보)
- 임계값(+6dB, 1500Hz, 200Hz)은 드라이버 스펙 연동 전까지의 보수적 일반값 — AKG/프로필
  모델(H)이 생기면 SpeakerProfile의 실제 Xmax/Fs로 정교화 가능
- `validateBiquad`의 위반 처리가 passthrough 전체 무효화라 다소 거칠음 — 부분 재조정
  알고리즘으로 개선 여지
- mobile/Pro 코드 100% 복제 — 공유 패키지화하면 두 곳 동시 유지보수 부담 해소 가능(ACM
  항목의 기존 중복 문제와 동일 선상)

### 다음 세션
C(Factory/User 레이어 분리) 진행 여부 확인 필요.

### 커밋
`f0d6bac` — feat(mobile): Safety Validation Layer 구현 — AOS 항목 D, 3개 진입점 강제 적용

---

## Factory/User Layer 분리 완료 (AOS 항목 C, 2026-07-05)

### 배경
직전 gap analysis: mobile의 "Factory"가 하드코딩된 빈 배열이라 우연히 안전할 뿐 설계된
보호가 아니었음. mobile은 이름 기반 다중 프리셋 저장 기능 자체가 없어(My Tune = 슬롯
1개, 사용자가 이름을 짓지 않음) Pro와 같은 "이름 충돌로 Factory를 덮어쓰는" 위험은
애초에 없었음 — 그래서 mobile 쪽 작업은 상대적으로 가벼움(Pro 쪽이 실질적 마이그레이션
작업의 핵심).

### 수정 내용
- `lib/core/factory_preset.dart`(신규): `FactoryPreset` 불변 클래스(setter 없음) +
  `kFactoryPresetFlat`("보정 없는 평탄 기준값", 밴드 0개) + `kFactoryPresets` 리스트.
  실제 공장 캘리브레이션 데이터가 없어(기존 HANDOFF 기록과 동일 원칙 — 가짜 데이터
  금지) 콘텐츠 자체는 이전과 같은 "빈 배열"이지만, 이제는 이름/설명이 있는 진짜 불변
  객체로 존재. SharedPreferences 등 어떤 저장소에도 쓰지 않고 코드에 직접 내장
- `preset_bar.dart`: `factory`/`reference` case가 이제 `kFactoryPresetFlat.bands`를
  참조(이전엔 각자 `const []` 리터럴을 따로 갖고 있었음 — 단일 소스로 통합)

### Safety Validation Layer(D) 확인 — 손대지 않고 통과 여부만 검증
Factory 선택 시에도 `preset_bar.dart:_select`가 그대로 `DspCompiler.compileAll(peaks)`
→`bleProvider.sendPackets()` 경로를 타므로, 직전 세션에 `compileAll` 내부에 심어둔
`DspSafety.validateBandGain` 검증을 동일하게 통과한다(코드 변경 없이 확인만 함).

### 알려진 한계
- mobile에 이름 기반 다중 프리셋 저장 기능이 생기면(현재는 없음) 그때 Pro와 동일한
  예약어 가드(`isReservedPresetName` 패턴)를 추가해야 함 — 지금은 애초에 이름을
  받지 않아 가드가 필요 없음
- Factory 콘텐츠가 "완전 평탄"이라 실제 공장 최적화값과는 다름 — 진짜 공장 캘리브레이션
  데이터가 생기면 `kFactoryPresetFlat`의 `bands`를 채우면 됨(구조는 이미 준비됨)

### 다음 세션
H(AKG 프로필 모델) 진행 여부 확인 필요. 상세 마이그레이션/설계 내용은 Pro 쪽
HANDOFF.md 참고(이번 세션의 실질적 작업은 Pro 쪽이 더 큼).

### 커밋
`ce7fc85` — feat(mobile): Factory/User Layer 분리 — AOS 항목 C

---

## AKG-ready Profile Model 추가 완료 (gap analysis 항목 H, 마지막, 2026-07-05)

### 배경
gap analysis 4개 후보(B/C/D/H) 중 마지막. AKG(Acoustic Knowledge Graph)는 기기/드라이버/
공간/측정/튜닝/선호 관계를 저장하는 계층 — MVP에서는 실제 그래프 DB 없이, 각 엔티티가
서로의 ID를 참조하는 필드만 있으면 충분하다는 전제로 진행.

### 기존에 이미 있던 노드
- **User**: `AuthState.userId`(`auth_controller.dart`, 커스텀 REST API 기반)
- **Device**: `TunaiDevice`(`device_service.dart`, `serial`이 사실상 deviceId)
- **Preset**: `MyTuneStorage`(My Tune 단일 슬롯), `FactoryPreset`(직전 세션에 추가)

### 없던 것 중 이번에 추가한 것
- **`lib/core/akg/measurement_session.dart`**: `MeasurementSession` — 측정 1회의
  메타데이터(id, timestamp, deviceId, userId, spaceType, peakCount, iterations,
  residualErrorDb, converged). `MeasurementSessionStore`가 SharedPreferences에
  append-only로 최근 200개까지 저장. **이게 부수적으로 기존 gap analysis 항목
  E(Measurement History — 그때는 "없음"으로 판정됨)도 같이 메워준다** — 이전엔
  `SpectrumSnapshot`의 3슬롯(before/afterAi/current)뿐이라 시계열 이력이 전혀
  없었는데, 이제 매 측정마다 이력이 쌓임(단, 지금은 저장만 하고 조회 UI는 없음 —
  "기존 UI 변경 최소화" 지침에 따름)
- **`lib/core/akg/user_preference_signal.dart`**: `UserPreferenceSignal` — 사용자가
  프리셋을 select/rollback/save/delete했는지 로그(id, timestamp, deviceId, userId,
  action, presetLabel). `UserPreferenceSignalStore`가 동일하게 최근 200개까지 저장.
  지금 당장 아무도 이 데이터를 분석하지 않음 — 나중에 AIE가 참조할 수 있게 저장만

### 연결 지점 (기존 UI/로직 변경 최소화, 훅만 추가)
- `measurement_controller.dart`: `startMeasurement`/`startClosedLoop`가
  `MeasurementStep.done`에 도달하는 3개 지점(단일 측정, Closed Loop 수렴, Closed
  Loop 최대반복) 모두에서 `_recordSession()` 호출(fire-and-forget, 실패해도 측정
  흐름에 영향 없음)
- `preset_bar.dart`: `_select()`가 프리셋 적용 후 `_recordPreferenceSignal()` 호출
  (Factory 선택은 `rollback`, 나머지는 `select`), `_save()`가 My Tune 저장 후
  `_recordSaveSignal()` 호출(`save`)

### 관계(엣지) 표현 방식
그래프 DB 없이 ID 참조 필드만으로 표현 — 예: `MeasurementSession.deviceId` →
`TunaiDevice.serial`, `MeasurementSession.userId` → `AuthState.userId`. 나중에 실제
그래프 DB로 옮길 때 이 필드들이 그대로 엣지가 된다.

### 확인
`flutter analyze` — 0 issues. **실기기 테스트는 못 함** — 코드 리뷰 수준으로만 검증.
저장 자체가 fire-and-forget try/catch로 감싸여 있어 실패해도 기존 기능(측정/프리셋
적용)에 영향 없음을 코드로 확인.

### Gap Analysis 4개 항목 전체 마무리
- **B (DSP Platform abstraction)** — 이미 있었음(확인만)
- **C (Factory/User Layer 분리)** — 완료(직전 세션)
- **D (Safety Validation Layer)** — 완료(그 전 세션)
- **H (AKG-ready Profile Model)** — 완료(이번 세션)

남은 후보: **AIP(클라우드 동기화)** — 이번 세션 의도적으로 스킵(로컬 데이터 모델만).
지금 쌓이기 시작한 `MeasurementSession`/`UserPreferenceSignal`이 나중에 AIP로 동기화될
1순위 후보.

### 다음 세션
다음 우선순위 제안 필요 — 후보: (1) 실기기 테스트 밀린 것들 전부 한번에 검증(ADAU1701
XO 매핑, ADAU1466 PEQ/Delay, 이번 세션들의 Safety/Factory/AKG 로직), (2) AIP 트랙
착수(로컬에 쌓인 AKG 데이터를 클라우드로 동기화), (3) mobile/Pro 코드 중복 해소(ACM
계층 등 여러 곳에서 반복 발견됨).

### 커밋
(다음 커밋 예정)

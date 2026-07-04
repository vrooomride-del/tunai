# TUNAI 마스터플랜 현황판

> 이 표는 매 세션 시작/종료 시 갱신한다.
> 새 작업으로 새기 전에 반드시 먼저 읽고, 세션 끝나면 변경된 항목만 갱신해서 다음 HANDOFF.md에 그대로 옮긴다.

**업데이트: 2026-07-04 (ADAU1701 신 펌웨어 반영 — 표준 5워드 biquad, writeCrossover 활성화. ⚠️ 실기기 신 펌웨어 플래시 필수)**

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
(다음 커밋 예정)

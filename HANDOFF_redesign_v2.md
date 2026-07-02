# TUNAI 마스터플랜 현황판

> 이 표는 매 세션 시작/종료 시 갱신한다.
> 새 작업으로 새기 전에 반드시 먼저 읽고, 세션 끝나면 변경된 항목만 갱신해서 다음 HANDOFF.md에 그대로 옮긴다.

**업데이트: 2026-07-02 (전면 UX 재설계 v2 완료 — 모바일 CONNECT/MEASURE/AI/LISTEN/MORE)**

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

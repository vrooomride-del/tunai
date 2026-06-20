# TUNAI 마스터플랜 현황판

> 이 표는 매 세션 시작/종료 시 갱신한다.  
> 새 작업으로 새기 전에 반드시 먼저 읽고, 세션 끝나면 변경된 항목만 갱신해서 다음 HANDOFF.md에 그대로 옮긴다.

**업데이트: 2026-06-21 (커뮤니티 진단 + fps 버그 수정, 모바일 감도매칭 이식)**

---

## A. 제품 플로우 6단계 현황 (모바일 + Pro)

| # | 단계 | 모바일 상태 | Pro 상태 | 비고 |
|---|---|---|---|---|
| 1 | 스피커/DSP 보드 탐지 | ✅ 완료 | ✅ 완료 (BLE+UART VID/PID) | ADAU1466 stub 유지 |
| 2 | 유닛 물성 기반 크로스오버 제안 | ✅ T/S+FRD+감도매칭 완료 | ✅ 크로스오버+감도매칭 완료, 위상정합은 펌웨어 대기 | — |
| 3 | DSP 자동 적용 (트위터 보호) | ✅ 완료 | — | — |
| 4 | 측정→AI 튜닝→APPLY (+Closed Loop) | ✅ 완료 | ✅ 완료 | Closed Loop: 모바일+Pro 둘 다 실시 완료 |
| 5 | 폰용 Pro 모드 | ⏸ 설계완료, FRD 임포트 완료. 선행조건: ADAU1466 보드 도착 | — | — |
| 6 | 커뮤니티 공유/판매 | ✅ 다운로드→적용 루프 완성 (fps 버그 수정). 판매 미구현 | ✅ 동일 | COMMUNITY_AUDIT.md 참고 |

---

## B. 특허 정합성 현황

| 특허 | 핵심 청구항 | 구현 상태 | 데드라인 |
|---|---|---|---|
| A. SonicCore (6/9 출원) | 청구항1: CCV | ✅ 실시 완료 | 국내우선권 2027-06-09 |
| A. SonicCore | 청구항8: 인클로저 해시 매칭 | ✅ 실시 완료 | 〃 |
| B. Closed Loop (6/12 출원) | 청구항1: 반복수렴 루프 | ✅ 모바일+Pro 둘 다 실시 완료 | 국내우선권 2027-06-12 |
| C. Modular Tuning Plate | 가변 포트 노브 | ⏸ 미출원 | 트리거 대기 |

---

## C. 하드웨어 트랙

| 항목 | 상태 |
|---|---|
| JAB4 + ICP5 브링업 | ✅ 해결 |
| ADAU1466 어댑터 | stub, 보드 도착 대기 |
| Pro 포트 자동감지/UART 탐지 | ✅ 완료 |
| Pro/모바일 위상정합 DSP 전달 | ⏸ SigmaStudio Delay 블록 추가 필요 (실물 PC 작업) |

---

## D. 전체 잔여 작업 후보

| 항목 | 작업 가능 여부 | 비고 |
|---|---|---|
| 커뮤니티 판매 기능 | ⏳ 가능하나 대형 작업 | 결제 연동(인앱결제 or PG사) + 서버 정산 로직 필요. COMMUNITY_AUDIT.md 참고 |
| 공유 시 측정 없으면 빈 프리셋 방지 UX | ✅ 소형 | 측정 없으면 SHARE 버튼 비활성화 또는 경고 |
| Pro _applyPreset 후 APPLY 안내 snackbar | ✅ 소형 | 현재 DSP state만 업데이트, 유저가 APPLY 눌러야 함을 안내 없음 |
| 위상정합 펌웨어(Delay 블록) 추가 | ❌ 실물 PC 필요 | SigmaStudio 작업 |
| ADAU1466 어댑터 구현 | ❌ 보드 도착 대기 | 물리적 전제조건 |
| Modular Tuning Plate 출원 | ❌ 설계 확정 대기 | 외부 공개 전 필수 |

---

## 이번 세션 작업 — 커뮤니티 진단 + fps 버그 수정

### 진단 결과 요약 (COMMUNITY_AUDIT.md 전문)

**다운로드→적용 루프:**
- 모바일 `_downloadAndApply()`: fps_json → ResonancePeak → DspCompiler.compileAll() → BLE sendPackets() ✅ 완성
- Pro `_applyPreset()`: fps_json → PeqBand → dspProvider 상태 업데이트 → 유저 APPLY 버튼 (의도된 설계) ✅

**치명적 버그 발견 + 수정:**
```dart
// 이전 (community_screen.dart:396)
fps: [], // 항상 빈 리스트

// 수정
final mPeaks = ref.read(measurementProvider).peaks;
final fps = mPeaks.map((p) => {'frequency': p.frequency, 'gain': p.gain, 'q': p.q}).toList();
fps: fps,
```
커밋: `88aea3f`

**판매 기능:**
- API 파라미터 `price: 0` 1개만 존재, UI/결제 흐름 전무 (0%)

### 이번 세션 추가 — 모바일 감도매칭 이식

- `adau1701_adapter.dart`: `_gainWoofer = 7`, `_gainTweeter = 6` (SigmaStudio 확인값)
- `_CrossoverCard`: 트위터 FRD 있을 때 "감도 매칭 적용" 버튼 표시
- `_applySensitivityMatch()`: FRD 우선 / T/S sensitivity 폴백, 최저 감도 기준 gain cut
- 커밋: `89125a6`

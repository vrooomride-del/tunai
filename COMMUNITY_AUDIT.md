# 커뮤니티 기능 감사 (Community Feature Audit)

> 작성: 2026-06-21  
> 목적: 다운로드→적용 루프 완성도 + 판매 기능 현황 진단

---

## 요약

| 항목 | 모바일 | Pro |
|---|---|---|
| 프리셋 목록 조회 (trending / latest / match) | ✅ | ✅ |
| 인클로저 해시 매칭 필터 | ✅ | ✅ |
| 프리셋 다운로드 → BLE/DSP 적용 | ✅ | ✅ (DSP state 로드 → APPLY 버튼) |
| **프리셋 공유 (fps 전송)** | ✅ **이번 세션 수정** | ✅ |
| 좋아요 / 댓글 | ✅ | ✅ |
| 게시판 (글쓰기 / 댓글) | ✅ | ✅ |
| **판매 기능 (가격/결제)** | ❌ 미구현 | ❌ 미구현 |

---

## 1. 다운로드 → 적용 루프

### 모바일 (`community_screen.dart`)

**완성된 것**
- `_downloadAndApply()`: `preset['fps_json']` → `ResonancePeak` 파싱 → `DspCompiler.compileAll()` → `bleProvider.notifier.sendPackets()` 전송
- BLE 미연결 시: 다운로드 완료 안내 snackbar + 재시도 유도 (로컬 저장 없음 — 현재 UX 허용 가능)
- 결과: 다운로드→적용 루프 **완성** (서버가 fps_json을 반환하는 것을 전제)

**수정된 갭 (이번 세션)**
```dart
// 이전 (버그)
fps: [], // 항상 빈 리스트 — 공유 프리셋에 필터 데이터 없음

// 수정 후
final mPeaks = ref.read(measurementProvider).peaks;
final fps = mPeaks.map((p) => {
  'frequency': p.frequency, 'gain': p.gain, 'q': p.q,
}).toList();
fps: fps, // 실제 PEQ 피크 데이터 포함
```

영향: 이전에 공유된 프리셋은 모두 `fps_json: []` → "필터 데이터가 없는 프리셋입니다." 오류 발생.  
수정 후부터 공유하는 프리셋은 정상 적용됨.

### Pro (`tunai_pro/lib/features/community/community_screen.dart`)

**완성된 것**
- `_applyPreset()`: `fps_json` → `PeqBand` 파싱 → `dspProvider.notifier.updateOutputBand()` 상태 업데이트
- 유저가 DSP 화면에서 APPLY 버튼을 눌러야 하드웨어에 전송됨 (의도된 설계 — 프리뷰 후 적용)
- `_shareCurrentDsp()`: `dspProvider.outputs[selectedOutput].bands` → `fps_json` 포함 정상 업로드 (**버그 없음**)

---

## 2. 인클로저 해시 매칭

### 모바일
- `_presetSort == 'match'` → `ApiService.getPresets(hash: _myHash())`
- `_myHash()`: `EnclosureHash.fromProfile(volumeL, portLengthMm, portDiamMm)`
- 클라이언트 측 완성. 서버가 `enclosure_hash` 컬럼으로 필터링하는 것을 전제.

### Pro
- 동일 구조, `EnclosureHash.fromEnclosure()` 사용.

---

## 3. 판매 기능 현황

**API 층**: `ApiService.uploadPreset(price: int = 0)` — 파라미터는 준비됨  
**클라이언트**: 가격 입력 UI 없음, 결제 흐름 없음, 구매 버튼 없음  
**결론**: 인프라의 0% — API 파라미터 1개만 존재

### 구현에 필요한 것 (이번 세션 범위 밖)
- 업로드 다이얼로그: 가격 입력 필드 추가 (`price` 파라미터 연결)
- 프리셋 카드: 가격 표시 + "구매" 버튼
- 결제 연동: 인앱결제(StoreKit/Google Play) 또는 PG사 연동
- 서버: 구매 확인 → 다운로드 권한 발급 로직
- 정산 로직

**권장**: 결제 설계부터 별도 세션에서 진행. 인앱결제는 플랫폼 수수료(30%)로 인해  
외부 결제(PG사) 선호 여부도 결정 필요.

---

## 4. 잔여 갭 (이번 세션 미처리)

| 항목 | 상태 | 비고 |
|---|---|---|
| 공유 시 측정 없으면 fps=[] 그대로 공유 가능 | ⚠️ | 측정 안 한 상태에서 SHARE 탭 → 빈 프리셋 공유됨. UX 개선 여지 있음 |
| 서버 enclosure_hash 필터링 실제 작동 여부 | 미확인 | 클라이언트 코드만 확인, 서버 코드 미열람 |
| Pro: 다운로드 후 APPLY 안내 없음 | ⚠️ | 유저가 DSP 탭으로 이동해야 함을 snackbar에 안내하면 좋음 |

---

## 결론

다운로드→적용 루프는 모바일 1개 버그(`fps: []`) 수정으로 **완성**.  
판매 기능은 설계부터 필요한 대형 작업 — 이번 세션 범위 밖.

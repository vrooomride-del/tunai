# TUNAI Closed Loop 반복 수렴 루프 설계

> 특허 청구항 1: "apply → re-measure → converge → retry" 루프  
> 작성일: 2026-06-20  
> 상태: 설계 전용 (구현 미완료)

---

## 개요

현재 플로우는 open loop:
```
측정 → DSP 컴파일 → BLE 전송 → 끝
```

Closed Loop 목표:
```
측정 → DSP 컴파일 → BLE 전송 → 재측정 → 수렴 확인 → (미수렴 시 반복)
```

---

## 수렴 기준 (Convergence Threshold)

재측정 결과와 이전 측정 결과 간 차이로 판단.

```
잔류 오차 = max(|newPeak.magnitude - avg|) — 각 피크 주파수 위치에서
```

- **수렴**: 모든 피크 주파수에서 잔류 오차 < **1.5 dB**
- **미수렴**: 잔류 오차 >= 1.5 dB → retry
- 최대 반복 횟수: **3회** (무한 루프 방지)

*1.5 dB는 인간 청각의 JND(Just Noticeable Difference) 기준. 조정 가능.*

---

## 루프 구조 (의사 코드)

```dart
Future<void> startClosedLoopMeasurement({SpeakerProfile? speakerProfile}) async {
  const maxIterations = 3;
  const convergenceThresholdDb = 1.5;

  List<ResonancePeak> lastPeaks = [];
  List<RegisterPacket> lastPackets = [];

  for (int iteration = 0; iteration < maxIterations; iteration++) {
    // 1. 측정
    final bins = await _measure();                    // 핑크노이즈 + FFT + MicCalibration
    final peaks = AudioAnalyzer.detectPeaks(bins);

    // 2. T/S 안전범위 적용
    final safePeaks = _applySafetyProfile(peaks, speakerProfile);

    // 3. DSP 컴파일 + BLE 전송
    final packets = DspCompiler.compileAll(safePeaks);
    await bleController.sendPackets(packets);

    // 4. DSP 안정화 대기 (ADAU1701 Safeload 처리 시간)
    await Future.delayed(const Duration(milliseconds: 200));

    // 5. 수렴 확인
    if (iteration > 0 && _hasConverged(peaks, lastPeaks, convergenceThresholdDb)) {
      _reportConverged(iteration + 1, peaks);
      return;
    }

    lastPeaks = safePeaks;
    lastPackets = packets;

    _updateStatus('반복 ${iteration + 1}/$maxIterations 완료 — 재측정 중...');
  }

  // 최대 반복 초과 → 마지막 결과로 확정
  _reportMaxIterationsReached(lastPeaks);
}

bool _hasConverged(
  List<ResonancePeak> current,
  List<ResonancePeak> previous,
  double thresholdDb,
) {
  if (previous.isEmpty) return false;
  // 이전 피크 주파수 근방(±10%) 에서 현재 최대 에너지와 비교
  for (final prev in previous) {
    final near = current.where(
      (p) => (p.frequency - prev.frequency).abs() / prev.frequency < 0.10,
    );
    if (near.isEmpty) continue;
    final maxGain = near.map((p) => p.gain.abs()).reduce(max);
    if (maxGain >= thresholdDb) return false;
  }
  return true;
}
```

---

## 삽입 위치

| 위치 | 파일 | 비고 |
|---|---|---|
| 루프 진입점 | `measurement_controller.dart` | `startMeasurement()` 대체 또는 래핑 |
| DSP 전송 후 대기 | 기존 `BleController.sendPackets()` 이후 | 200ms 하드웨어 안정화 |
| 상태 표시 | `MeasurementStep` enum | `converging` 스텝 추가 필요 |
| UI 표시 | `home_screen.dart` | "반복 2/3 중..." 진행 표시 |

---

## 새로 추가할 MeasurementStep

```dart
enum MeasurementStep {
  idle,
  generatingNoise,
  playing,
  recording,
  analyzing,
  detectingPeaks,
  compiling,
  converging,   // ← 신규: DSP 적용 후 재측정 대기
  done,
  error,
}
```

---

## MeasurementState 확장

```dart
class MeasurementState {
  // 기존 필드 유지...
  final int iteration;           // 현재 반복 회수 (0-based)
  final bool hasConverged;       // 수렴 성공 여부
  final double? residualErrorDb; // 마지막 잔류 오차 (dB)
}
```

---

## UI 변경 사항

`home_screen.dart` 측정 진행 표시:
- "반복 1/3 — 공진 검출 중..." → "반복 1/3 — DSP 적용 중..." → "반복 2/3 — 재측정 중..."
- 수렴 시: "수렴 완료 (반복 2회, 잔류 오차 0.8dB)"
- 최대 반복 초과: "최대 반복 도달 (3회) — 마지막 결과 적용"

---

## 제약 및 고려사항

1. **측정 시간**: 1회 측정 = 약 12초 (핑크노이즈 10초 + 처리 2초). 3회 루프 = 최대 36초.
2. **BLE 전송 타이밍**: ADAU1701 Safeload는 오디오 프레임 경계에서 처리됨. 200ms 대기 후 재측정 권장.
3. **과보정 방지**: 루프가 진행될수록 이전 보정 위에 추가 보정이 쌓임. 누적 gain이 -24dB 초과 시 경고.
4. **피크 추적 일관성**: 반복 간 같은 피크를 추적하려면 주파수 ±10% 매칭 사용 (위 `_hasConverged` 참고).
5. **사용자 취소**: 루프 도중 취소 가능해야 함 — `_isCancelled` 플래그 또는 `CancellationToken` 패턴.

---

## 구현 우선순위

현재 open loop도 실용적으로 동작함. Closed Loop는 다음 조건 충족 시 구현:
- [ ] ADAU1701 실기기 연결 및 측정 파이프라인 검증 완료
- [ ] `hpfPramAddr = 0x000B` 하드웨어 확인
- [ ] 1회 측정 → DSP 적용 → 청감 테스트 통과 후

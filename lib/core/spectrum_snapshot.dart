import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'audio_analyzer.dart';

/// LISTEN 탭의 Before/After/현재 3색 오버레이가 참조하는 스펙트럼 스냅샷.
/// - before: MEASURE에서 측정한 원본 곡선
/// - afterAi: AI APPLY 직후, before 곡선에 AI 밴드를 합성한 예상 곡선 (재측정 없이 미리보기)
/// - current: 사용자가 FINE TUNE 등으로 추가 조정한 최신 곡선 (기본값은 afterAi와 동일)
class SpectrumSnapshot {
  final List<FrequencyBin>? before;
  final List<FrequencyBin>? afterAi;
  final List<FrequencyBin>? current;

  const SpectrumSnapshot({this.before, this.afterAi, this.current});
}

final spectrumSnapshotProvider =
    StateNotifierProvider<SpectrumSnapshotController, SpectrumSnapshot>(
  (ref) => SpectrumSnapshotController(),
);

class SpectrumSnapshotController extends StateNotifier<SpectrumSnapshot> {
  SpectrumSnapshotController() : super(const SpectrumSnapshot());

  void setBefore(List<FrequencyBin> bins) {
    state = SpectrumSnapshot(before: bins);
  }

  /// AI가 제안한 밴드를 before 곡선에 합성해 "After" 예상 곡선을 만든다.
  /// 실제 재측정 대신 각 밴드를 옥타브 단위 가우시안 근사로 합산 — LISTEN 탭 미리보기 전용, DSP 전송값에는 영향 없음.
  ///
  /// `peaks`가 비어 있으면(보정 없음 TunePlan) `_applyPeaksToBins`가 delta=0인,
  /// before와 완전히 동일한 곡선을 반환하게 되어 — 실제로는 "생성된 예상 곡선이
  /// 없다"는 뜻인데도 afterAi가 non-null로 남아 "두 곡선이 있는 것처럼" 보이는
  /// 실기 버그의 원인이었다. 빈 peaks는 명시적으로 [clearAfter]로 처리한다.
  void applyPeaks(List<ResonancePeak> peaks) {
    if (peaks.isEmpty) {
      clearAfter();
      return;
    }
    final base = state.before;
    if (base == null) return;
    final after = _applyPeaksToBins(base, peaks);
    state = SpectrumSnapshot(before: state.before, afterAi: after, current: after);
  }

  /// 이 세션에 실제로 적용할 보정이 없을 때(빈 TunePlan) 호출 — before는 그대로
  /// 유지하고 afterAi/current만 지워, 이전 Tune에서 남은 예상 곡선이 새 "보정
  /// 없음" 결과 화면을 오염시키지 않게 한다.
  void clearAfter() =>
      state = SpectrumSnapshot(before: state.before, afterAi: null, current: state.before);

  void setCurrent(List<FrequencyBin> bins) {
    state = SpectrumSnapshot(before: state.before, afterAi: state.afterAi, current: bins);
  }

  void reset() => state = const SpectrumSnapshot();

  /// [bins] 위에 [peaks]를 합성한 미리보기 곡선을 반환 (DSP 전송값에는 영향 없음)
  static List<FrequencyBin> previewWithPeaks(
          List<FrequencyBin> bins, List<ResonancePeak> peaks) =>
      _applyPeaksToBins(bins, peaks);

  static List<FrequencyBin> _applyPeaksToBins(
      List<FrequencyBin> bins, List<ResonancePeak> peaks) {
    return bins.map((b) {
      double delta = 0;
      for (final p in peaks) {
        if (b.frequency <= 0 || p.frequency <= 0) continue;
        final octaves = (math.log(b.frequency / p.frequency) / math.ln2).abs();
        final width = 1 / p.q.clamp(0.3, 16.0);
        delta += p.gain * math.exp(-0.5 * math.pow(octaves / width, 2));
      }
      return FrequencyBin(frequency: b.frequency, magnitude: b.magnitude + delta);
    }).toList();
  }
}

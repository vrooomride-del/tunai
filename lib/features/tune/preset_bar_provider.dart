import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/audio_analyzer.dart';

/// 상단 프리셋 바 항목 — 기존 보드선택 칩 자리를 대체.
/// 순서: Factory / Reference / AI Tune / My Tune / (배치 프리셋)
enum PresetBarSelection { factory, reference, aiTune, myTune, nearWall, desk, studio }

extension PresetBarSelectionLabel on PresetBarSelection {
  String get label => switch (this) {
        PresetBarSelection.factory => 'Factory',
        PresetBarSelection.reference => 'Reference',
        PresetBarSelection.aiTune => 'AI Tune',
        PresetBarSelection.myTune => 'My Tune',
        PresetBarSelection.nearWall => 'Near Wall',
        PresetBarSelection.desk => 'Desk',
        PresetBarSelection.studio => 'Studio',
      };
}

/// 배치 최적화 프리셋 — MEASURE의 위치 선택과 별개로, 측정 없이도 바로 적용 가능한 고정 EQ.
const kLocationPresetBands = {
  PresetBarSelection.desk: [
    ResonancePeak(frequency: 180, gain: -3.0, q: 3.0),
  ],
  PresetBarSelection.nearWall: [
    ResonancePeak(frequency: 90, gain: -3.5, q: 1.5),
  ],
  PresetBarSelection.studio: [
    ResonancePeak(frequency: 60, gain: -1.0, q: 0.7),
  ],
};

final presetBarSelectionProvider = StateProvider<PresetBarSelection?>((ref) => null);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/audio_analyzer.dart';

/// 취향 EQ 레이어 — AI가 만든 기본 EQ 위에 추가로 얹는 소량의 보정 밴드.
class TastePreset {
  final String id;
  final String label;
  final String labelKo;
  final String description;
  final List<ResonancePeak> bands;
  const TastePreset({required this.id, required this.label, required this.labelKo, required this.description, required this.bands});
}

const kTastePresets = [
  TastePreset(
    id: 'warm', label: 'Warm', labelKo: '따뜻하게', description: '따뜻하고 부드러운 소리',
    bands: [
      ResonancePeak(frequency: 120, gain: 2.5, q: 0.8),
      ResonancePeak(frequency: 8000, gain: -1.5, q: 0.7),
    ],
  ),
  TastePreset(
    id: 'neutral', label: 'Neutral', labelKo: '기본', description: '원음에 가까운 플랫한 소리',
    bands: [],
  ),
  TastePreset(
    id: 'studio', label: 'Studio', labelKo: 'Studio', description: '모니터링에 최적화',
    bands: [
      ResonancePeak(frequency: 60, gain: -1.5, q: 0.7),
      ResonancePeak(frequency: 3000, gain: 1.0, q: 1.0),
    ],
  ),
  TastePreset(
    id: 'vocal', label: 'Vocal', labelKo: '보컬', description: '보컬이 선명하게',
    bands: [
      ResonancePeak(frequency: 2500, gain: 2.5, q: 1.2),
      ResonancePeak(frequency: 300, gain: -1.0, q: 1.0),
    ],
  ),
  TastePreset(
    id: 'movie', label: 'Movie', labelKo: '영화', description: '저음 강조, 영화/게임용',
    bands: [
      ResonancePeak(frequency: 60, gain: 3.5, q: 0.8),
      ResonancePeak(frequency: 10000, gain: 1.5, q: 0.7),
    ],
  ),
  TastePreset(
    id: 'bright', label: 'Bright', labelKo: '선명하게', description: '고음 강조, 선명한 소리',
    bands: [
      ResonancePeak(frequency: 6000, gain: 3.0, q: 0.9),
      ResonancePeak(frequency: 12000, gain: 2.0, q: 0.8),
    ],
  ),
];

final selectedTasteProvider = StateProvider<TastePreset?>((ref) => null);

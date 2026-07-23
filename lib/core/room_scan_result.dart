import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'room_measurement.dart';

/// Consumer-facing result after a Room Scan completes.
/// No DSP/PEQ/frequency graph data is exposed here.
class RoomScanResultCard {
  final String id;
  final String labelEn;
  final String labelKo;
  final String descriptionEn;
  final String descriptionKo;
  final String? evidenceKey;

  const RoomScanResultCard({
    required this.id,
    required this.labelEn,
    required this.labelKo,
    required this.descriptionEn,
    required this.descriptionKo,
    this.evidenceKey,
  });

  String label({bool ko = false}) => ko ? labelKo : labelEn;
  String description({bool ko = false}) => ko ? descriptionKo : descriptionEn;

  Map<String, dynamic> toJson() => {
        'id': id,
        'labelEn': labelEn,
        'labelKo': labelKo,
        'descriptionEn': descriptionEn,
        'descriptionKo': descriptionKo,
        if (evidenceKey != null) 'evidenceKey': evidenceKey,
      };
  factory RoomScanResultCard.fromJson(Map<String, dynamic> j) =>
      RoomScanResultCard(
        id: j['id'] as String,
        labelEn: j['labelEn'] as String,
        labelKo: j['labelKo'] as String,
        descriptionEn: j['descriptionEn'] as String,
        descriptionKo: j['descriptionKo'] as String,
        evidenceKey: j['evidenceKey'] as String?,
      );
}

const kDefaultResultCards = [
  RoomScanResultCard(
    id: 'balance',
    labelEn: 'Space Balance',
    labelKo: '공간 밸런스',
    descriptionEn:
        'TUNAI checked how your space shapes the sound at your listening position.'
        '\n→ The sound was refined for better overall balance.',
    descriptionKo: 'TUNAI가 청취 위치에서 공간의 울림을 확인했습니다.'
        '\n→ 더 균형 잡힌 소리로 정리했습니다.',
  ),
  RoomScanResultCard(
    id: 'bass',
    labelEn: 'Bass Control',
    labelKo: '저역 정리',
    descriptionEn: 'Nearby surfaces can make bass feel heavier than intended.'
        '\n→ Bass was tightened for a clearer, more controlled sound.',
    descriptionKo: '벽과 책상 주변의 영향으로 저역이 부풀 수 있습니다.'
        '\n→ 저역이 더 단단하고 또렷하게 들리도록 정리했습니다.',
  ),
  RoomScanResultCard(
    id: 'voice',
    labelEn: 'Vocal Clarity',
    labelKo: '보컬 선명도',
    descriptionEn: 'Reflections in your space can blur vocal presence.'
        '\n→ Vocals were adjusted to sound more natural and focused.',
    descriptionKo: '보컬 대역이 공간 반사로 흐려질 수 있습니다.'
        '\n→ 목소리가 더 자연스럽게 앞으로 나오도록 조정했습니다.',
  ),
  RoomScanResultCard(
    id: 'comfort',
    labelEn: 'Listening Comfort',
    labelKo: '청취 편안함',
    descriptionEn: 'TUNAI checked the balance for longer listening.'
        '\n→ The sound was refined to feel more comfortable over time.',
    descriptionKo: '오래 들을 때 피로감을 줄이는 방향을 확인했습니다.'
        '\n→ 더 편안하게 들을 수 있도록 소리의 균형을 다듬었습니다.',
  ),
];

class RoomScanResult {
  final int schemaVersion;
  final String? measurementId;
  final bool validatedMeasurement;
  final String roomType;
  final String micProfileName;
  final DateTime completedAt;
  final String confidence;
  final List<RoomScanResultCard> cards;

  const RoomScanResult({
    this.schemaVersion = 1,
    this.measurementId,
    this.validatedMeasurement = false,
    required this.roomType,
    required this.micProfileName,
    required this.completedAt,
    required this.confidence,
    required this.cards,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        if (measurementId != null) 'measurementId': measurementId,
        'validatedMeasurement': validatedMeasurement,
        'roomType': roomType,
        'micProfileName': micProfileName,
        'completedAt': completedAt.toIso8601String(),
        'confidence': confidence,
        'cards': cards.map((c) => c.toJson()).toList(),
      };

  factory RoomScanResult.fromJson(Map<String, dynamic> j) => RoomScanResult(
        schemaVersion: j['schemaVersion'] as int? ?? 0,
        measurementId: j['measurementId'] as String?,
        validatedMeasurement: j['validatedMeasurement'] as bool? ?? false,
        roomType: j['roomType'] as String,
        micProfileName: j['micProfileName'] as String,
        completedAt: DateTime.parse(j['completedAt'] as String),
        confidence: j['confidence'] as String,
        cards: (j['cards'] as List)
            .map((c) => RoomScanResultCard.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  static RoomScanResult fromMeasurement(RoomMeasurement measurement) {
    if (!measurement.isValid) {
      throw StateError(
          'An invalid measurement cannot become a RoomScanResult.');
    }
    return RoomScanResult(
      schemaVersion: roomMeasurementSchemaVersion,
      measurementId: measurement.id,
      validatedMeasurement: true,
      roomType: measurement.roomType,
      micProfileName: measurement.microphoneProfileId,
      completedAt: measurement.capturedAt,
      confidence: _confidenceFromMeasurement(measurement),
      cards: _cardsFromMeasurement(measurement),
    );
  }
}

String _confidenceFromMeasurement(RoomMeasurement measurement) {
  var score = 0.0;
  score += measurement.timing.durationCompleteness.clamp(0.0, 1.0) * 0.3;
  score += measurement.levels.signalPresent ? 0.25 : 0;
  score += measurement.levels.severelyClipped ? 0 : 0.2;
  // Signal headroom above the minimum usable level. Replaces a placeholder
  // weight on `consistencyMetric`, which is always exactly 1.0 by
  // construction: any measurement reaching this point already passed
  // RoomMeasurementValidator.validate(), which requires every bin to be
  // finite — so "fraction of finite bins" could never actually vary here.
  // RMS headroom genuinely varies with real capture quality: a recording
  // barely above the noise floor scores near 0; one with 3x headroom above
  // the minimum usable level scores 1. Uses the same `levels.rms` already
  // computed for validation — no new measurement.
  final rmsHeadroom = RoomMeasurementValidator.minimumRms <= 0
      ? 1.0
      : (((measurement.levels.rms / RoomMeasurementValidator.minimumRms) - 1.0)
              .clamp(0.0, 2.0)) /
          2.0;
  score += rmsHeadroom * 0.15;
  score += measurement.hasMicrophoneCalibration ? 0.1 : 0.05;

  // Repeatability gate. Everything above measures whether the CAPTURE was
  // well-formed — long enough, loud enough, not clipped — none of which can
  // tell a real room apart from ten seconds of noise. `consistencyMetric` now
  // carries a genuine split-half agreement (see `CaptureAnalysis.agreement`),
  // so a capture whose own two halves disagree can no longer be reported as
  // High confidence, which is exactly what real-device runs did while
  // returning completely different "resonances" every time.
  final consistency = measurement.consistencyMetric.clamp(0.0, 1.0);
  score *= 0.4 + 0.6 * consistency;
  if (score >= 0.85) return 'High';
  if (score >= 0.65) return 'Medium';
  return 'Low';
}

List<RoomScanResultCard> _cardsFromMeasurement(RoomMeasurement measurement) {
  final cards = <RoomScanResultCard>[];
  final bassPeaks = measurement.peaks
      .where((peak) => peak.frequency <= 200 && peak.gain <= -2.0)
      .toList();
  if (bassPeaks.isNotEmpty) {
    cards.add(const RoomScanResultCard(
      id: 'measured_bass',
      labelEn: 'Bass Response',
      labelKo: '저역 반응',
      descriptionEn:
          'The measurement found a noticeable low-frequency buildup at the listening position.',
      descriptionKo: '청취 위치에서 두드러지는 저역의 부풀림이 측정되었습니다.',
      evidenceKey: 'detected_peak_20_200hz',
    ));
  }
  final upperBassPeaks = measurement.peaks
      .where((peak) => peak.frequency > 200 && peak.gain <= -2.0)
      .toList();
  if (upperBassPeaks.isNotEmpty) {
    cards.add(const RoomScanResultCard(
      id: 'measured_balance',
      labelEn: 'Space Balance',
      labelKo: '공간 밸런스',
      descriptionEn:
          'The measurement found an uneven response that may affect overall balance at the listening position.',
      descriptionKo: '청취 위치의 전체적인 균형에 영향을 줄 수 있는 응답 차이가 측정되었습니다.',
      evidenceKey: 'detected_peak_200_500hz',
    ));
  }
  if (cards.isEmpty) {
    cards.add(const RoomScanResultCard(
      id: 'measured_neutral',
      labelEn: 'Space Analysis',
      labelKo: '공간 스캔',
      descriptionEn:
          'The measurement did not find a strong low-frequency buildup in the analyzed range.',
      descriptionKo: '분석한 범위에서 두드러지는 저역의 부풀림은 측정되지 않았습니다.',
      evidenceKey: 'no_bounded_peak_20_500hz',
    ));
  }
  return cards;
}

// ── Riverpod store ────────────────────────────────────────────────────────────
const _kKey = 'tunai_room_scan_result';

class RoomScanResultNotifier extends StateNotifier<RoomScanResult?> {
  RoomScanResultNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw != null) {
      try {
        final loaded =
            RoomScanResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        // Legacy records remain available but are explicitly unvalidated.
        state = loaded;
      } catch (_) {}
    }
  }

  Future<void> saveResult(RoomScanResult result) async {
    state = result;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(result.toJson()));
  }

  Future<void> clear() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}

final roomScanResultProvider =
    StateNotifierProvider<RoomScanResultNotifier, RoomScanResult?>(
        (_) => RoomScanResultNotifier());

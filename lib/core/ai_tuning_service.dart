import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/audio_analyzer.dart';
import 'speaker_profile.dart';

class AiTuningResult {
  final List<Map<String, dynamic>> bands;
  final String explanation;
  final bool isError;
  /// AI가 산정한 예상 음질 점수 (0-100). 백엔드가 아직 지원하지 않으면 null.
  final int? soundScore;

  const AiTuningResult({required this.bands, required this.explanation, this.isError = false, this.soundScore});

  factory AiTuningResult.fromJson(Map<String, dynamic> json) => AiTuningResult(
    bands: (json['bands'] as List? ?? [])
        .map((b) => Map<String, dynamic>.from(b as Map))
        .toList(),
    explanation: json['explanation'] ?? '',
    soundScore: (json['soundScore'] as num?)?.round(),
  );

  factory AiTuningResult.error(String msg) => AiTuningResult(bands: [], explanation: msg, isError: true);
}

/// 가장 최근 AI 튜닝 결과 — FINE TUNE 탭이 "AI가 만든 기본 EQ" 위에 취향 레이어를 얹을 때 참조
final lastAiResultProvider = StateProvider<AiTuningResult?>((ref) => null);

class AiTuningService {
  static final _functions = FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  static Future<AiTuningResult> suggest({
    required List<ResonancePeak> peaks,
    required String userRequest,
    SpeakerProfile? speakerProfile,
    String? location,
  }) async {
    try {
      debugPrint('[AI] Firebase Functions 호출 시작...');
      final callable = _functions.httpsCallable('aiTune');
      final result = await callable.call({
        'peaks': peaks.map((p) => {
          'frequency': p.frequency,
          'gain': p.gain,
          'q': p.q,
        }).toList(),
        'userRequest': userRequest,
        if (speakerProfile != null) 'speakerProfile': {
          'fs': speakerProfile.fs,
          'xmax': speakerProfile.xmax,
          'sensitivity': speakerProfile.sensitivity,
        },
        if (location != null) 'location': location,
      });
      debugPrint('[AI] 응답 수신 완료');
      return AiTuningResult.fromJson(Map<String, dynamic>.from(result.data));
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[AI] FirebaseFunctionsException: code=${e.code} message=${e.message} details=${e.details}');
      return AiTuningResult.error('AI 오류: ${e.message}');
    } catch (e) {
      debugPrint('[AI] 기타 에러: $e');
      return AiTuningResult.error('AI 응답 오류: $e');
    }
  }
}

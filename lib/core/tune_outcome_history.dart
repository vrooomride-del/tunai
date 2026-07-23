import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'consumer_sound_profile.dart';
import 'sound_preference.dart';

/// One real, already-happened Tune Apply outcome.
///
/// This is Closed Loop *preparation* structure only — the substrate for a
/// future step where AI reasoning could be grounded in what actually
/// happened the last time a Tune was applied for this room/speaker/
/// preference, instead of only the current measurement. Nothing here is fed
/// into [AiTuneOrchestrator]/`AiTuningService.suggest()` yet; that
/// connection is intentionally deferred rather than wired half-finished.
/// Every field traces back to something that genuinely happened (a real
/// deployment attempt and its real, already-computed Sound Score) — nothing
/// is projected or fabricated.
class TuneOutcomeRecord {
  final String tunePlanId;
  final String? measurementId;
  final SoundPreference preference;
  final bool usedAiRecommendation;
  final ConsumerDspDeploymentRecordResult result;
  final int? soundScoreBefore;
  final int? soundScoreAfter;
  final DateTime recordedAt;

  const TuneOutcomeRecord({
    required this.tunePlanId,
    this.measurementId,
    required this.preference,
    required this.usedAiRecommendation,
    required this.result,
    this.soundScoreBefore,
    this.soundScoreAfter,
    required this.recordedAt,
  });

  Map<String, dynamic> toJson() => {
        'tunePlanId': tunePlanId,
        if (measurementId != null) 'measurementId': measurementId,
        'preference': preference.toJson(),
        'usedAiRecommendation': usedAiRecommendation,
        'result': result.name,
        if (soundScoreBefore != null) 'soundScoreBefore': soundScoreBefore,
        if (soundScoreAfter != null) 'soundScoreAfter': soundScoreAfter,
        'recordedAt': recordedAt.toIso8601String(),
      };

  factory TuneOutcomeRecord.fromJson(Map<String, dynamic> json) =>
      TuneOutcomeRecord(
        tunePlanId: json['tunePlanId'] as String,
        measurementId: json['measurementId'] as String?,
        preference: SoundPreference.fromJson(json['preference'] as String?),
        usedAiRecommendation: json['usedAiRecommendation'] as bool? ?? false,
        result: ConsumerDspDeploymentRecordResult.values
            .byName(json['result'] as String),
        soundScoreBefore: json['soundScoreBefore'] as int?,
        soundScoreAfter: json['soundScoreAfter'] as int?,
        recordedAt: DateTime.parse(json['recordedAt'] as String),
      );
}

/// Keeps the last [maxEntries] real Tune Apply outcomes, most-recent first.
class TuneOutcomeHistory {
  static const _key = 'tunai_tune_outcome_history_v1';

  /// Small on purpose — this is a rolling recent-history buffer, not an
  /// analytics log.
  static const maxEntries = 5;

  static Future<void> record(TuneOutcomeRecord entry) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await _load(prefs);
    final next = [entry, ...existing].take(maxEntries).toList();
    await prefs.setString(
        _key, jsonEncode(next.map((e) => e.toJson()).toList()));
  }

  static Future<List<TuneOutcomeRecord>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return _load(prefs);
  }

  static Future<List<TuneOutcomeRecord>> _load(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) =>
              TuneOutcomeRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

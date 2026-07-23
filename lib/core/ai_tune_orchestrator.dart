import 'package:flutter/foundation.dart';

import 'acoustic_intelligence_context.dart';
import 'ai_tuning_service.dart';
import 'audio_analyzer.dart' show FrequencyBin, ResonancePeak;
import 'consumer_sound_profile.dart'
    show ConsumerDspDeploymentRecordResult, roomTypeLabelKo;
import 'room_measurement.dart';
import 'sound_preference.dart';
import 'sound_score_calculator.dart' show SoundScoreResult;
import 'speaker_profile.dart';
import 'tune_outcome_history.dart';
import 'tune_plan.dart';
import 'tune_safety_validator.dart';

/// Result of attempting an AI-shaped Tune on top of the existing rule-based
/// [TunePlan]. Never a hard failure from the caller's point of view: when AI
/// is unavailable, times out, returns something unusable, or nothing survives
/// [TuneSafetyValidator], [plan] is simply the original rule-based plan,
/// unchanged — "AI 실패 시 기존 Tune 정상 동작".
///
/// [aiFailureReason] is for logs/debugging only — it is never shown to the
/// user (the app never surfaces raw AI/network error text as a Tune result).
class AiTuneOrchestrationResult {
  final TunePlan plan;
  final bool usedAiRecommendation;
  final String? aiFailureReason;

  /// Internal decision bookkeeping (see [AiDecisionMetadata]) — never
  /// rendered in Consumer UI. Consumer copy is built separately from safe,
  /// already-validated facts (see `_AiExplainSection` in ai_screen.dart),
  /// never from this metadata directly.
  final AiDecisionMetadata metadata;

  const AiTuneOrchestrationResult({
    required this.plan,
    required this.usedAiRecommendation,
    this.aiFailureReason,
    required this.metadata,
  });
}

/// How much internal weight this Tune's origin deserves — derived purely
/// from real, already-known signals (measurement quality, and, when AI was
/// used, how many of its proposed bands actually survived
/// [TuneSafetyValidator]). Never a model-reported "confidence" score (the
/// backend doesn't provide one) and never fabricated — internal-only, for
/// logging/future tooling, never shown to the Consumer.
enum AiDecisionConfidence { high, medium, low }

/// Internal decision record for one [AiTuneOrchestrator.orchestrate] call —
/// "AI Decision Metadata": whether AI was used, why it fell back if not, how
/// many of its proposed bands passed validation, and the resulting
/// [AiDecisionConfidence]. Strictly internal bookkeeping (logging, future
/// admin/debug tooling, or feeding a later [TuneOutcomeRecord]) — the
/// Consumer app must never render any field of this class directly; the
/// existing `_AiExplainSection` (ai_screen.dart) already builds its
/// user-facing copy from separate, already-safe facts instead.
class AiDecisionMetadata {
  final bool usedAiRecommendation;
  final String? fallbackReason;
  final int proposedBandCount;
  final int validatedBandCount;
  final AiDecisionConfidence confidence;

  const AiDecisionMetadata({
    required this.usedAiRecommendation,
    this.fallbackReason,
    this.proposedBandCount = 0,
    this.validatedBandCount = 0,
    required this.confidence,
  });
}

/// The AI Provider boundary: matches [AiTuningService.suggest]'s signature.
/// [AiTuneOrchestrator] never imports Firebase/Gemini-specific types itself —
/// everything it needs from a provider is expressed through this typedef.
/// Swapping the current provider (Firebase Cloud Function → Gemini, see
/// [AiTuningService]) for a different one later means supplying a different
/// [AiSuggestFn] here, nothing more — no change to [AiTuneOrchestrator]'s own
/// logic. This also makes it injectable so tests can exercise
/// [AiTuneOrchestrator] without a live network call. Multiple simultaneous
/// providers/models are intentionally out of scope — this is a single
/// swappable slot, not a provider registry.
typedef AiSuggestFn = Future<AiTuningResult> Function({
  required List<ResonancePeak> peaks,
  required String userRequest,
  SpeakerProfile? speakerProfile,
  String? location,
  List<FrequencyBin>? spectrum,
  SoundScoreResult? soundScore,
});

/// Named form of the [AiSuggestFn] boundary — a future alternative provider
/// (a different backend/model) implements this interface and is handed to
/// [AiTuneOrchestrator] via [AiTuneOrchestrator.suggest] as `.suggest`,
/// nothing else changes. Only one provider is ever active at a time; this is
/// a swappable slot, not a registry, and no second implementation is built
/// here — [GeminiAiProvider] remains the only one.
abstract class AiProvider {
  Future<AiTuningResult> suggest({
    required List<ResonancePeak> peaks,
    required String userRequest,
    SpeakerProfile? speakerProfile,
    String? location,
    List<FrequencyBin>? spectrum,
    SoundScoreResult? soundScore,
  });
}

/// The current, and only, [AiProvider]: the existing Firebase Cloud
/// Function → Gemini call in [AiTuningService], unchanged. A thin wrapper —
/// all Gemini/Firebase-specific behavior still lives exclusively in
/// [AiTuningService].
class GeminiAiProvider implements AiProvider {
  const GeminiAiProvider();

  @override
  Future<AiTuningResult> suggest({
    required List<ResonancePeak> peaks,
    required String userRequest,
    SpeakerProfile? speakerProfile,
    String? location,
    List<FrequencyBin>? spectrum,
    SoundScoreResult? soundScore,
  }) =>
      AiTuningService.suggest(
        peaks: peaks,
        userRequest: userRequest,
        speakerProfile: speakerProfile,
        location: location,
        spectrum: spectrum,
        soundScore: soundScore,
      );
}

/// Orchestrates "AI interprets, TUNAI validates, DSP executes" for Tune
/// generation:
///
/// 1. The caller always has [TunePlan] `rulePlan` — [TunePlanner]'s
///    deterministic, already-safety-bounded output — ready as both the
///    guaranteed fallback and the metadata shell (id, safety bounds,
///    measurement linkage) for the final plan either way.
/// 2. Asks the current AI provider (Firebase → Gemini today, via
///    [AiTuningService], reached only through the swappable [AiSuggestFn]
///    boundary — see [suggest]) for a recommendation shaped by the same
///    real measurement, preference, and speaker context.
/// 3. Treats every AI-proposed band as an *unvalidated proposal* — never
///    trusted, never written to DSP directly. Each one is parsed
///    defensively (malformed entries are dropped, not guessed at) and run
///    through [TuneSafetyValidator]: the exact same frequency/gain/Q/
///    band-count/aggregate-cut checks [TunePlanner]'s own output must
///    already satisfy.
/// 4. Only replaces `rulePlan`'s bands with the AI-validated ones if at
///    least one survives; otherwise the deterministic rule-based plan is
///    returned exactly as it was passed in.
class AiTuneOrchestrator {
  const AiTuneOrchestrator({
    this.validator = const TuneSafetyValidator(),
    this.timeout = const Duration(seconds: 12),
    // Defaults to the current AiProvider (GeminiAiProvider, which itself
    // just forwards to AiTuningService.suggest — see that class). A future
    // provider swap only needs a different value here.
    this.suggest = AiTuningService.suggest,
    this.loadRecentOutcomes = TuneOutcomeHistory.load,
  });

  final TuneSafetyValidator validator;

  /// Client-side ceiling so a slow/unresponsive AI call can never make Tune
  /// creation hang. This is a HARD UX budget: the user is staring at
  /// "Creating your Sound..." for the whole of it.
  ///
  /// Real-device logs show every `aiTune` call — cold AND warm — overrunning
  /// this, with the response arriving only after we had already given up:
  ///
  ///   [AI] Firebase Functions 호출 시작...
  ///   [AI-TUNE] recommendation unavailable ... TimeoutException after 12s
  ///   [AI] 응답 수신 완료          <- the answer, arriving after we quit
  ///
  /// Raising this to 35s (past the function's own 30s server timeout) was
  /// tried and reverted: it does let a result through, but only by making the
  /// user wait half a minute on every single Tune, for an enhancement that is
  /// optional by design — the deterministic rule-based plan is already
  /// complete before this call even starts.
  ///
  /// The real defect is server-side latency on the `aiTune` function, and it
  /// has to be fixed there (keep an instance warm / reduce model latency).
  /// Until then this stays at a wait a user will actually tolerate, and Tune
  /// falls back to the rule-based plan — which is honest, not degraded: that
  /// plan is what every observed run has shipped anyway.
  final Duration timeout;

  final AiSuggestFn suggest;

  /// Closed Loop: real, already-recorded Apply outcomes (see
  /// tune_outcome_history.dart) — injectable so tests don't depend on
  /// SharedPreferences state. Best-effort: a failure here never blocks Tune
  /// generation, it just means no history context is available this time.
  final Future<List<TuneOutcomeRecord>> Function() loadRecentOutcomes;

  /// Falls back to the rule-based [rulePlan] unchanged, with [AiDecisionMetadata]
  /// recording why. Shared by every early-return path below so fallback
  /// bookkeeping can't drift out of sync across them.
  AiTuneOrchestrationResult _fallback(
    TunePlan rulePlan,
    CaptureQualityStatus quality,
    String reason, {
    int proposedBandCount = 0,
    int validatedBandCount = 0,
  }) =>
      AiTuneOrchestrationResult(
        plan: rulePlan,
        usedAiRecommendation: false,
        aiFailureReason: reason,
        metadata: AiDecisionMetadata(
          usedAiRecommendation: false,
          fallbackReason: reason,
          proposedBandCount: proposedBandCount,
          validatedBandCount: validatedBandCount,
          confidence: _deriveConfidence(
            usedAi: false,
            quality: quality,
            proposedBandCount: proposedBandCount,
            validatedBandCount: validatedBandCount,
          ),
        ),
      );

  Future<AiTuneOrchestrationResult> orchestrate({
    required RoomMeasurement measurement,
    required TunePlan rulePlan,
    required SoundPreference preference,
    SpeakerProfile? speakerProfile,
    // The current, real, already-computed Sound Score (see
    // SoundScoreCalculator) — optional extra grounding for the AI's
    // reasoning about how much correction is actually warranted. Never a
    // fabricated number: whatever the caller passes must already come from
    // a real computation on the real measured curve.
    SoundScoreResult? currentScore,
  }) async {
    // ── Role 1: Acoustic Reasoning ────────────────────────────────────────
    // Gathers and structures the real context the AI reasons over — Room
    // Measurement, Preference, Speaker, and Closed Loop history — without
    // yet asking for or producing any recommendation. Kept separate from
    // Role 2 below so a future change to *what* gets reasoned about doesn't
    // need to touch *how* a recommendation is requested/validated.
    final context = await _reason(measurement, preference, speakerProfile);

    // ── Role 2: Tune Recommendation ───────────────────────────────────────
    // Requests a recommendation from the current AiProvider, then treats it
    // as an unvalidated proposal end-to-end: parsed defensively, then run
    // through TuneSafetyValidator — the same gate TunePlanner's own rule-based
    // output must satisfy. Only replaces rulePlan's bands if something
    // real survives; otherwise rulePlan is returned unchanged.
    //
    // (Role 3, User Explanation, deliberately does not live here — see
    // `_AiExplainSection` in ai_screen.dart, which builds Consumer-facing
    // copy only from already-safe, already-validated facts, never from raw
    // AI output or this method's internals.)
    AiTuningResult result;
    try {
      result = await suggest(
        peaks: measurement.peaks,
        // Still only ever built from real, structured facts (room type,
        // measurement quality, the chosen preset preference) — never
        // arbitrary free text, so there is no path for unconstrained user
        // input to reach the LLM prompt.
        userRequest: _buildUserRequest(context),
        speakerProfile: speakerProfile,
        location: measurement.roomType,
        spectrum: measurement.frequencyBins,
        soundScore: currentScore,
      ).timeout(timeout);
    } catch (error) {
      debugPrint('[AI-TUNE] recommendation unavailable, using rule-based '
          'Tune: $error');
      return _fallback(rulePlan, measurement.quality, error.toString());
    }

    if (result.isError || result.bands.isEmpty) {
      debugPrint('[AI-TUNE] no usable recommendation, using rule-based '
          'Tune: ${result.explanation}');
      return _fallback(rulePlan, measurement.quality, result.explanation);
    }

    final candidates = <TuneCorrectionBand>[
      for (final raw in result.bands)
        if (_parseBand(raw, measurement.id) case final band?) band,
    ];
    if (candidates.isEmpty) {
      debugPrint('[AI-TUNE] AI response contained no parseable bands, '
          'using rule-based Tune.');
      return _fallback(
          rulePlan, measurement.quality, 'unparseable_ai_response',
          proposedBandCount: result.bands.length);
    }

    final validated = validator.validate(candidates);
    if (!validated.isDeployable) {
      debugPrint('[AI-TUNE] every AI-proposed band failed safety '
          'validation, using rule-based Tune: '
          '${validated.rejectedBands.map((r) => r.reason).toList()}');
      return _fallback(
          rulePlan, measurement.quality, 'all_ai_bands_rejected_by_safety_validator',
          proposedBandCount: candidates.length, validatedBandCount: 0);
    }

    return AiTuneOrchestrationResult(
      plan: validated.rebuild(rulePlan),
      usedAiRecommendation: true,
      metadata: AiDecisionMetadata(
        usedAiRecommendation: true,
        proposedBandCount: candidates.length,
        validatedBandCount: validated.approvedBands.length,
        confidence: _deriveConfidence(
          usedAi: true,
          quality: measurement.quality,
          proposedBandCount: candidates.length,
          validatedBandCount: validated.approvedBands.length,
        ),
      ),
    );
  }

  /// Role 1 (Acoustic Reasoning): loads real Closed Loop history
  /// (best-effort — never blocks Tune generation) and bundles it with the
  /// real measurement/preference/speaker into one [AcousticIntelligenceContext].
  Future<AcousticIntelligenceContext> _reason(
    RoomMeasurement measurement,
    SoundPreference preference,
    SpeakerProfile? speakerProfile,
  ) async {
    List<TuneOutcomeRecord> recentOutcomes = const [];
    try {
      recentOutcomes = await loadRecentOutcomes();
    } catch (error) {
      debugPrint('[AI-TUNE] outcome history unavailable, continuing '
          'without it: $error');
    }
    return AcousticIntelligenceContext(
      measurement: measurement,
      preference: preference,
      speakerProfile: speakerProfile,
      recentOutcomes: recentOutcomes,
    );
  }

  /// Purely derived from real, already-known signals — never a fabricated
  /// or model-reported score. See [AiDecisionConfidence].
  AiDecisionConfidence _deriveConfidence({
    required bool usedAi,
    required CaptureQualityStatus quality,
    required int proposedBandCount,
    required int validatedBandCount,
  }) {
    final qualityOk = quality == CaptureQualityStatus.valid;
    if (usedAi) {
      final fullyValidated =
          proposedBandCount > 0 && validatedBandCount == proposedBandCount;
      return qualityOk && fullyValidated
          ? AiDecisionConfidence.high
          : AiDecisionConfidence.medium;
    }
    return qualityOk ? AiDecisionConfidence.medium : AiDecisionConfidence.low;
  }

  /// Builds a richer, still fully-structured (no free text) request string —
  /// real room type + real measurement quality + the user's chosen preset
  /// preference + a factual summary of recent real Apply outcomes, if any —
  /// so the AI reasons with more of the same real context
  /// [AcousticIntelligenceContext] already bundles, not just the preference
  /// alone.
  String _buildUserRequest(AcousticIntelligenceContext context) {
    final measurement = context.measurement;
    final roomLabel = roomTypeLabelKo(measurement.roomType);
    final qualityKo = switch (measurement.quality) {
      CaptureQualityStatus.valid => '측정 신뢰도 높음',
      CaptureQualityStatus.degraded => '측정 신뢰도 보통',
      CaptureQualityStatus.invalid ||
      CaptureQualityStatus.cancelled =>
        '측정 신뢰도 낮음',
    };
    final base =
        '$roomLabel · $qualityKo. ${context.preference.description(ko: true)}';
    final outcomeSummary = _buildOutcomeSummary(context.recentOutcomes);
    return outcomeSummary == null ? base : '$base $outcomeSummary';
  }

  /// Factual, real-data-only summary of the recent Apply history — counts
  /// of real successes/failures and the most recent preference/result, so
  /// the AI can factor in "what actually happened last time" without any
  /// simulated re-measurement or invented verification data. Returns null
  /// when there is no history yet (first Tune ever, or history unavailable).
  String? _buildOutcomeSummary(List<TuneOutcomeRecord> outcomes) {
    if (outcomes.isEmpty) return null;
    final succeeded = outcomes
        .where((o) => o.result == ConsumerDspDeploymentRecordResult.applied)
        .length;
    final failed = outcomes.length - succeeded;
    final latest = outcomes.first; // most-recent-first, see TuneOutcomeHistory
    final buffer = StringBuffer('최근 조정 이력: 성공 $succeeded회');
    if (failed > 0) buffer.write(', 실패 $failed회');
    buffer.write('. 최근 선호: ${latest.preference.description(ko: true)}');
    final before = latest.soundScoreBefore;
    final after = latest.soundScoreAfter;
    if (before != null && after != null) {
      buffer.write(after > before ? ', 직전 결과 개선됨' : ', 직전 결과 변화 적음');
    }
    return buffer.toString();
  }

  /// Defensive parse: any missing/non-finite/disabled field drops the band
  /// entirely rather than guessing a value. `evidenceReference` is tagged
  /// `ai:` so it stays distinguishable from rule-engine bands
  /// (`evidenceReference` for those is `<measurementId>:peak:<freq>`).
  TuneCorrectionBand? _parseBand(
      Map<String, dynamic> raw, String measurementId) {
    final frequency = (raw['frequency'] as num?)?.toDouble();
    final gainDb = (raw['gainDb'] as num?)?.toDouble();
    final q = (raw['q'] as num?)?.toDouble();
    final enabled = raw['enabled'] as bool? ?? true;
    if (frequency == null || gainDb == null || q == null || !enabled) {
      return null;
    }
    if (!frequency.isFinite || !gainDb.isFinite || !q.isFinite) return null;
    return TuneCorrectionBand(
      frequencyHz: frequency,
      gainDb: gainDb,
      q: q,
      evidenceReference: 'ai:$measurementId:${frequency.toStringAsFixed(1)}',
      safetyValidated: true,
    );
  }
}

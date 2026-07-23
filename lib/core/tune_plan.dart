import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_analyzer.dart';
import 'broadband_tone_analyzer.dart';
import 'fine_tune_adjustments.dart';
import 'room_measurement.dart';
import 'sound_preference.dart';

const int tunePlanSchemaVersion = 1;
const String tunePlanAlgorithmVersion = 'bounded_room_cut_v1';

enum TuneDeploymentStatus {
  notDeployed,
  deploying,
  applied,
  failed,
  unknown,
}

class TuneSafetyBounds {
  final double minimumFrequencyHz;
  final double maximumFrequencyHz;
  final int maximumBands;
  final double maximumCutDb;
  final double minimumQ;
  final double maximumQ;
  final double minimumSpacingHz;
  final double minimumSpacingRatio;
  final double aggregateCutLimitDb;

  /// Largest positive gain a band may carry. Defaults to 0 — cut-only, the
  /// long-standing Consumer policy, so every existing caller and stored plan
  /// behaves exactly as before.
  ///
  /// Broadband tonal correction needs a small amount of boost to be able to
  /// lift a region that measured BELOW its neighbours; a cut-only correction
  /// can only ever make the quiet parts of a room quieter still. 3dB is not a
  /// chosen-by-feel number: it is the ceiling
  /// `ConsumerDspDeploymentExecutor` itself accepts (gain -6..+3dB), so a
  /// plan built to this bound is deployable without an Apply-time surprise.
  final double maximumBoostDb;

  const TuneSafetyBounds({
    this.minimumFrequencyHz = 20,
    this.maximumFrequencyHz = 500,
    this.maximumBands = 4,
    this.maximumCutDb = 6,
    this.minimumQ = 0.7,
    this.maximumQ = 8,
    this.minimumSpacingHz = 12,
    this.minimumSpacingRatio = 0.15,
    this.aggregateCutLimitDb = 12,
    this.maximumBoostDb = 0,
  });

  /// Consumer full-range profile: broadband tonal balance across everything a
  /// phone microphone can be trusted on, not just room modes below 500Hz.
  ///
  /// The 500Hz default ceiling exists because narrow modal correction above
  /// the room's transition frequency is not meaningful. Broadband correction
  /// is a different job with a different valid range, so it gets its own
  /// bounds rather than loosening the modal ones. The deployment protocol
  /// already permits 20Hz-20kHz; 8kHz is the microphone limit, not a protocol
  /// limit.
  /// The floor stays at the modal 20Hz — [BroadbandToneAnalyzer] already
  /// declines to look below 60Hz itself, and raising this would throw away
  /// genuine low room modes (real captures found them at 51Hz and 58Hz).
  static const consumerFullRange = TuneSafetyBounds(
    maximumFrequencyHz: BroadbandToneAnalyzer.maxFrequencyHz,
    maximumBoostDb: BroadbandToneAnalyzer.maximumBoostDb,
  );

  Map<String, dynamic> toJson() => {
        'minimumFrequencyHz': minimumFrequencyHz,
        'maximumFrequencyHz': maximumFrequencyHz,
        'maximumBands': maximumBands,
        'maximumCutDb': maximumCutDb,
        'minimumQ': minimumQ,
        'maximumQ': maximumQ,
        'minimumSpacingHz': minimumSpacingHz,
        'minimumSpacingRatio': minimumSpacingRatio,
        'aggregateCutLimitDb': aggregateCutLimitDb,
        'maximumBoostDb': maximumBoostDb,
      };

  factory TuneSafetyBounds.fromJson(Map<String, dynamic> json) =>
      TuneSafetyBounds(
        minimumFrequencyHz: (json['minimumFrequencyHz'] as num).toDouble(),
        maximumFrequencyHz: (json['maximumFrequencyHz'] as num).toDouble(),
        maximumBands: json['maximumBands'] as int,
        maximumCutDb: (json['maximumCutDb'] as num).toDouble(),
        minimumQ: (json['minimumQ'] as num).toDouble(),
        maximumQ: (json['maximumQ'] as num).toDouble(),
        minimumSpacingHz: (json['minimumSpacingHz'] as num).toDouble(),
        minimumSpacingRatio: (json['minimumSpacingRatio'] as num).toDouble(),
        aggregateCutLimitDb: (json['aggregateCutLimitDb'] as num).toDouble(),
        // Absent in plans stored before broadband correction existed —
        // defaults to the old cut-only behaviour rather than failing to load.
        maximumBoostDb: (json['maximumBoostDb'] as num?)?.toDouble() ?? 0,
      );
}

/// Where a correction band's target originates. Today only [roomMode] is
/// ever produced — the pipeline only measures and corrects real room-mode
/// resonances (see `AudioAnalyzer.roomModeSearchCeilingHz`). [speakerCharacter]
/// is reserved structure for a future correction source, once real
/// per-speaker FRD reference data is available (see
/// `SpeakerProfile.wooferFrd`/`tweeterFrd`) to separate what the room is
/// doing from what the speaker itself is doing — nothing is produced with
/// that value yet; it exists so Room vs Speaker corrections can be told
/// apart in the data model without a later breaking migration.
enum TuneCorrectionSource {
  roomMode,
  speakerCharacter,

  /// Broad tonal balance across the full analysed range, from
  /// [BroadbandToneAnalyzer] — a whole region pulled back toward the
  /// measurement's own local trend, rather than a narrow resonance notched
  /// out. This is what a listener actually hears most of, and it is measured
  /// far more reliably than individual modes.
  tonalBalance,

  /// A small, bounded, factory-anchored tonal NUDGE toward the user's stated
  /// listening preference (Phase 7) — measurement-independent, generated
  /// deterministically by the engine (never by AI) and validated by the same
  /// Safety Validator as every other band. This is what makes TUNAI personal
  /// rather than a room EQ: taste shapes the sound even when the room needs no
  /// correction, always within safe limits and without re-voicing the factory
  /// character.
  preferenceTarget;

  String toJson() => name;

  static TuneCorrectionSource fromJson(String? value) => switch (value) {
        'speakerCharacter' => TuneCorrectionSource.speakerCharacter,
        'tonalBalance' => TuneCorrectionSource.tonalBalance,
        'preferenceTarget' => TuneCorrectionSource.preferenceTarget,
        _ => TuneCorrectionSource.roomMode,
      };
}

class TuneCorrectionBand {
  final double frequencyHz;
  final double gainDb;
  final double q;
  final String evidenceReference;
  final bool safetyValidated;
  final TuneCorrectionSource source;

  const TuneCorrectionBand({
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    required this.evidenceReference,
    required this.safetyValidated,
    this.source = TuneCorrectionSource.roomMode,
  });

  Map<String, dynamic> toJson() => {
        'frequencyHz': frequencyHz,
        'gainDb': gainDb,
        'q': q,
        'evidenceReference': evidenceReference,
        'safetyValidated': safetyValidated,
        'source': source.toJson(),
      };

  factory TuneCorrectionBand.fromJson(Map<String, dynamic> json) =>
      TuneCorrectionBand(
        frequencyHz: (json['frequencyHz'] as num).toDouble(),
        gainDb: (json['gainDb'] as num).toDouble(),
        q: (json['q'] as num).toDouble(),
        evidenceReference: json['evidenceReference'] as String,
        safetyValidated: json['safetyValidated'] as bool,
        source: TuneCorrectionSource.fromJson(json['source'] as String?),
      );
}

class RejectedTuneCandidate {
  final double? frequencyHz;
  final String reason;

  const RejectedTuneCandidate(
      {required this.frequencyHz, required this.reason});

  Map<String, dynamic> toJson() => {
        if (frequencyHz != null) 'frequencyHz': frequencyHz,
        'reason': reason,
      };

  factory RejectedTuneCandidate.fromJson(Map<String, dynamic> json) =>
      RejectedTuneCandidate(
        frequencyHz: (json['frequencyHz'] as num?)?.toDouble(),
        reason: json['reason'] as String,
      );
}

class TunePlan {
  final int schemaVersion;
  final String id;
  final String sourceMeasurementId;
  final String algorithmVersion;
  final DateTime createdAt;
  final List<TuneCorrectionBand> bands;
  final List<RejectedTuneCandidate> rejectedCandidates;
  final TuneSafetyBounds safetyBounds;
  final CaptureQualityStatus measurementQuality;
  final double measurementConsistency;
  final List<String> warnings;
  final TuneDeploymentStatus deploymentStatus;

  const TunePlan({
    this.schemaVersion = tunePlanSchemaVersion,
    required this.id,
    required this.sourceMeasurementId,
    this.algorithmVersion = tunePlanAlgorithmVersion,
    required this.createdAt,
    required this.bands,
    required this.rejectedCandidates,
    required this.safetyBounds,
    required this.measurementQuality,
    required this.measurementConsistency,
    required this.warnings,
    this.deploymentStatus = TuneDeploymentStatus.notDeployed,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'sourceMeasurementId': sourceMeasurementId,
        'algorithmVersion': algorithmVersion,
        'createdAt': createdAt.toIso8601String(),
        'bands': bands.map((band) => band.toJson()).toList(),
        'rejectedCandidates':
            rejectedCandidates.map((candidate) => candidate.toJson()).toList(),
        'safetyBounds': safetyBounds.toJson(),
        'measurementQuality': measurementQuality.name,
        'measurementConsistency': measurementConsistency,
        'warnings': warnings,
        'deploymentStatus': deploymentStatus.name,
      };

  factory TunePlan.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != tunePlanSchemaVersion) {
      throw const FormatException('Unsupported TunePlan schema.');
    }
    final plan = TunePlan(
      schemaVersion: json['schemaVersion'] as int,
      id: json['id'] as String,
      sourceMeasurementId: json['sourceMeasurementId'] as String,
      algorithmVersion: json['algorithmVersion'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      bands: (json['bands'] as List)
          .map((entry) => TuneCorrectionBand.fromJson(
              Map<String, dynamic>.from(entry as Map)))
          .toList(),
      rejectedCandidates: (json['rejectedCandidates'] as List)
          .map((entry) => RejectedTuneCandidate.fromJson(
              Map<String, dynamic>.from(entry as Map)))
          .toList(),
      safetyBounds: TuneSafetyBounds.fromJson(
          Map<String, dynamic>.from(json['safetyBounds'] as Map)),
      measurementQuality: CaptureQualityStatus.values
          .byName(json['measurementQuality'] as String),
      measurementConsistency:
          (json['measurementConsistency'] as num).toDouble(),
      warnings: (json['warnings'] as List).cast<String>(),
      deploymentStatus: TuneDeploymentStatus.values
          .byName(json['deploymentStatus'] as String),
    );
    TunePlanner.validatePlan(plan);
    return plan;
  }
}

class TunePlanner {
  final TuneSafetyBounds bounds;
  final DateTime Function() now;

  const TunePlanner({
    this.bounds = TuneSafetyBounds.consumerFullRange,
    required this.now,
  });

  /// Generates a Tune from the real measured [measurement], optionally
  /// shaped by a [SoundPreference] and/or [FineTuneAdjustments]. Both only
  /// ever scale down each real measured peak's gain (weights ≤ 1.0) and/or
  /// narrow the result further (Q blend, band count) before the existing
  /// [TuneSafetyBounds] checks below run unchanged — neither invents a
  /// correction, touches a frequency region the room scan didn't actually
  /// measure, or pulls a result outside the safety envelope, only further
  /// inside it. [SoundPreference.balanced] with [FineTuneAdjustments.neutral]
  /// (the defaults) reproduce the exact prior unscaled behavior, so every
  /// existing call site is unaffected.
  TunePlan generate(
    RoomMeasurement measurement, {
    SoundPreference preference = SoundPreference.balanced,
    FineTuneAdjustments fineTune = FineTuneAdjustments.neutral,
  }) {
    _validateMeasurement(measurement);
    debugPrint('[TUNE_TRACE] TunePlanner.generate: '
        'measurement.peaks(input)=${measurement.peaks.length} '
        '${measurement.peaks.map((p) => '${p.frequency.toStringAsFixed(1)}Hz/'
            '${p.gain.toStringAsFixed(1)}dB/Q${p.q.toStringAsFixed(1)}').toList()}');
    final rejected = <RejectedTuneCandidate>[];
    final scaledPeaks = [
      for (final peak in measurement.peaks)
        ResonancePeak(
          frequency: peak.frequency,
          gain: peak.gain *
              preference.weightFor(peak.frequency) *
              (peak.frequency < SoundPreference.midBandThresholdHz
                  ? fineTune.bassWeight
                  : fineTune.warmWeight) *
              fineTune.vocalWeight,
          q: peak.q,
        ),
    ];
    final candidates = [...scaledPeaks]..sort((left, right) {
        final byDepth = left.gain.compareTo(right.gain);
        return byDepth != 0
            ? byDepth
            : left.frequency.compareTo(right.frequency);
      });
    debugPrint('[TUNE_TRACE] scaled candidates=${candidates.length} '
        '(preference=${preference.name}, after weightFor/fineTune scaling)');
    final accepted = <TuneCorrectionBand>[];
    var aggregateCut = 0.0;

    // Broadband tonal balance FIRST, before individual room modes.
    //
    // Deliberate priority, not an ordering accident. The deployable band
    // budget is small (3 on real hardware), and of the corrections available
    // the broad ones are both the most audible and by far the most reliably
    // measured — each averages hundreds of FFT bins, where a narrow mode is
    // 1-2 bins wide and moves with microphone position. Spending the budget
    // on modes first, as this planner used to, spent it on the least
    // trustworthy corrections. Modes still get whatever budget is left over.
    for (final tone in BroadbandToneAnalyzer.analyze(measurement.frequencyBins)) {
      final band = TuneCorrectionBand(
        frequencyHz: tone.frequencyHz,
        gainDb: tone.gainDb,
        q: tone.q,
        evidenceReference:
            '${measurement.id}:tone:${tone.frequencyHz.toStringAsFixed(1)}',
        safetyValidated: true,
        source: TuneCorrectionSource.tonalBalance,
      );
      final reason = _bandRejection(band, accepted, aggregateCut);
      if (reason != null) {
        debugPrint('[TUNE_TRACE] REJECT tone ${band.frequencyHz.toStringAsFixed(1)}Hz '
            '${band.gainDb.toStringAsFixed(1)}dB reason=$reason');
        rejected.add(RejectedTuneCandidate(
            frequencyHz: band.frequencyHz, reason: reason));
        continue;
      }
      accepted.add(band);
      if (band.gainDb < 0) aggregateCut += band.gainDb.abs();
    }
    debugPrint('[TUNE_TRACE] broadband bands accepted=${accepted.length}');

    for (final peak in candidates) {
      final reason = _candidateRejection(peak, accepted, aggregateCut);
      if (reason != null) {
        debugPrint('[TUNE_TRACE] REJECT ${peak.frequency.toStringAsFixed(1)}Hz '
            '${peak.gain.toStringAsFixed(1)}dB Q${peak.q.toStringAsFixed(1)} '
            'reason=$reason');
        rejected.add(RejectedTuneCandidate(
          frequencyHz: peak.frequency.isFinite ? peak.frequency : null,
          reason: reason,
        ));
        continue;
      }
      final cut = math.min(peak.gain.abs(), bounds.maximumCutDb);
      if (aggregateCut + cut > bounds.aggregateCutLimitDb) {
        debugPrint('[TUNE_TRACE] REJECT ${peak.frequency.toStringAsFixed(1)}Hz '
            'reason=aggregate_cut_limit (aggregateCut=$aggregateCut, cut=$cut, '
            'limit=${bounds.aggregateCutLimitDb})');
        rejected.add(RejectedTuneCandidate(
          frequencyHz: peak.frequency,
          reason: 'aggregate_cut_limit',
        ));
        continue;
      }
      // "Space" blends between a broader/gentler curve (minimumQ) and the
      // room's own real measured sharpness — never sharper than what was
      // actually measured, and always within the existing Q bounds.
      final measuredQ = peak.q.clamp(bounds.minimumQ, bounds.maximumQ).toDouble();
      final blendedQ =
          bounds.minimumQ + (measuredQ - bounds.minimumQ) * fineTune.spaceWeight;
      accepted.add(TuneCorrectionBand(
        frequencyHz: peak.frequency,
        gainDb: -cut,
        q: blendedQ.clamp(bounds.minimumQ, bounds.maximumQ).toDouble(),
        evidenceReference:
            '${measurement.id}:peak:${peak.frequency.toStringAsFixed(3)}',
        safetyValidated: true,
      ));
      aggregateCut += cut;
    }

    // "Detail" — how many of the already safety-validated candidate bands to
    // actually keep, most-significant (largest cut) first. Purely a further
    // narrowing of `accepted`, so it can never introduce anything unsafe;
    // `null` (the default) makes no change to prior behavior.
    if (fineTune.detailBandLimit != null &&
        accepted.length > fineTune.detailBandLimit!) {
      for (final dropped in accepted.skip(fineTune.detailBandLimit!)) {
        rejected.add(RejectedTuneCandidate(
          frequencyHz: dropped.frequencyHz,
          reason: 'fine_tune_detail_limit',
        ));
      }
      accepted.removeRange(fineTune.detailBandLimit!, accepted.length);
    }

    accepted
        .sort((left, right) => left.frequencyHz.compareTo(right.frequencyHz));
    // Preference/Fine-Tune-suffixed only when non-default, so the default
    // (balanced + neutral) id is byte-for-byte identical to before these
    // parameters existed — no behavior change for any existing caller. A
    // different preference/Fine Tune for the same measurement produces
    // materially different bands, so it must not collide with the default
    // plan's id.
    final idSuffix =
        (preference == SoundPreference.balanced ? '' : ':${preference.name}') +
            fineTune.idSuffix;
    final plan = TunePlan(
      id: '${measurement.id}:$tunePlanAlgorithmVersion$idSuffix',
      sourceMeasurementId: measurement.id,
      createdAt: now().toUtc(),
      bands: List.unmodifiable(accepted),
      rejectedCandidates: List.unmodifiable(rejected),
      safetyBounds: bounds,
      measurementQuality: measurement.quality,
      measurementConsistency: measurement.consistencyMetric,
      warnings: List.unmodifiable(measurement.warnings),
    );
    debugPrint('[TUNE_TRACE] FINAL bands=${accepted.length} '
        'rejected=${rejected.length} '
        '(${rejected.map((r) => r.reason).toSet().toList()}) '
        'accepted=${accepted.map((b) => '${b.frequencyHz.toStringAsFixed(1)}Hz/'
            '${b.gainDb.toStringAsFixed(1)}dB').toList()}');
    validatePlan(plan);
    return plan;
  }

  void _validateMeasurement(RoomMeasurement measurement) {
    if (measurement.schemaVersion != roomMeasurementSchemaVersion ||
        measurement.algorithmVersion != roomMeasurementAlgorithmVersion) {
      throw const FormatException('Unsupported measurement version.');
    }
    // A degraded-quality measurement (lower confidence, but not rejected —
    // see RoomMeasurementValidator.classifyQuality) still produces a Tune;
    // only invalid/cancelled captures are blocked here.
    if (!measurement.isValid) {
      throw StateError('A validated measurement is required.');
    }
    if (measurement.frequencyBins.isEmpty ||
        measurement.frequencyBins
            .any((bin) => !bin.frequency.isFinite || !bin.magnitude.isFinite)) {
      throw const FormatException('The measurement spectrum is invalid.');
    }
    for (var i = 1; i < measurement.frequencyBins.length; i++) {
      if (measurement.frequencyBins[i].frequency <=
          measurement.frequencyBins[i - 1].frequency) {
        throw const FormatException('The measurement spectrum is not ordered.');
      }
    }
    if (measurement.timing.sampleCount <= 0 ||
        measurement.timing.fileSizeBytes <= 44 ||
        measurement.timing.actualSampleRate == null ||
        measurement.timing.channelCount <= 0 ||
        !measurement.consistencyMetric.isFinite ||
        measurement.consistencyMetric < 0 ||
        measurement.consistencyMetric > 1) {
      throw const FormatException('The measurement metadata is invalid.');
    }
    if (measurement.peaks.any((peak) =>
        !peak.frequency.isFinite || !peak.gain.isFinite || !peak.q.isFinite)) {
      throw const FormatException('A detected feature is non-finite.');
    }
  }

  /// Gate for an already-formed correction band (broadband tonal corrections
  /// arrive as bands, not as resonance candidates). Applies the same bounds
  /// `TuneSafetyValidator` will re-check before deployment, so nothing enters
  /// a plan that could not actually be deployed.
  String? _bandRejection(
    TuneCorrectionBand band,
    List<TuneCorrectionBand> accepted,
    double aggregateCut,
  ) {
    if (!band.frequencyHz.isFinite ||
        !band.gainDb.isFinite ||
        !band.q.isFinite) {
      return 'non_finite_candidate';
    }
    if (band.frequencyHz < bounds.minimumFrequencyHz ||
        band.frequencyHz > bounds.maximumFrequencyHz) {
      return 'frequency_out_of_bounds';
    }
    if (band.gainDb.abs() < 1) return 'not_supported_cut';
    if (band.gainDb > bounds.maximumBoostDb) {
      return bounds.maximumBoostDb <= 0
          ? 'not_supported_cut'
          : 'gain_exceeds_maximum_boost';
    }
    if (band.gainDb < 0 && band.gainDb.abs() > bounds.maximumCutDb) {
      return 'gain_exceeds_maximum_cut';
    }
    if (band.q < bounds.minimumQ || band.q > bounds.maximumQ) {
      return 'q_out_of_bounds';
    }
    if (accepted.length >= bounds.maximumBands) return 'maximum_bands';
    for (final other in accepted) {
      final requiredSpacing = math.max(
        bounds.minimumSpacingHz,
        math.min(other.frequencyHz, band.frequencyHz) *
            bounds.minimumSpacingRatio,
      );
      if ((other.frequencyHz - band.frequencyHz).abs() < requiredSpacing) {
        return 'overlapping_candidate';
      }
    }
    if (band.gainDb < 0 &&
        aggregateCut + band.gainDb.abs() > bounds.aggregateCutLimitDb) {
      return 'aggregate_cut_limit';
    }
    return null;
  }

  String? _candidateRejection(
    ResonancePeak peak,
    List<TuneCorrectionBand> accepted,
    double aggregateCut,
  ) {
    if (!peak.frequency.isFinite || !peak.gain.isFinite || !peak.q.isFinite) {
      return 'non_finite_candidate';
    }
    if (peak.frequency < bounds.minimumFrequencyHz ||
        peak.frequency > bounds.maximumFrequencyHz) {
      return 'frequency_out_of_bounds';
    }
    if (peak.gain >= 0 || peak.gain.abs() < 1) return 'not_supported_cut';
    // Only a physically meaningless Q is fatal here. A finite, positive
    // measured Q that falls OUTSIDE [minimumQ, maximumQ] is not discarded —
    // it is clamped into bounds a few lines below (see `measuredQ`), and the
    // band that gets built therefore always carries an in-bounds Q, which
    // TuneSafetyValidator independently re-checks before deployment.
    //
    // This gate used to reject such peaks outright, which directly
    // contradicted that clamp and silently destroyed real corrections:
    // AudioAnalyzer._estimateQ clamps to [0.3, 16] (the range
    // RoomMeasurementValidator accepts), while these bounds are [0.7, 8]. At
    // the ~0.67Hz FFT bin resolution used for Room Scan, a genuinely sharp
    // room mode occupies only 1-2 bins and saturates at Q=16 — so on real
    // hardware EVERY detected peak could be thrown out as
    // `q_out_of_bounds`, yielding a zero-band plan. The user then saw
    // "no adjustment needed", with no Apply path and therefore no
    // Original/TUNAI comparison, despite a perfectly good measurement.
    if (peak.q <= 0) return 'q_out_of_bounds';
    if (accepted.length >= bounds.maximumBands) return 'maximum_bands';
    for (final band in accepted) {
      final requiredSpacing = math.max(
        bounds.minimumSpacingHz,
        math.min(band.frequencyHz, peak.frequency) * bounds.minimumSpacingRatio,
      );
      if ((band.frequencyHz - peak.frequency).abs() < requiredSpacing) {
        return 'overlapping_candidate';
      }
    }
    if (aggregateCut >= bounds.aggregateCutLimitDb) {
      return 'aggregate_cut_limit';
    }
    return null;
  }

  static void validatePlan(TunePlan plan) {
    if (plan.algorithmVersion != tunePlanAlgorithmVersion ||
        plan.deploymentStatus == TuneDeploymentStatus.applied ||
        plan.bands.length > plan.safetyBounds.maximumBands) {
      throw const FormatException('The TunePlan state is invalid.');
    }
    var aggregate = 0.0;
    for (final band in plan.bands) {
      if (!band.frequencyHz.isFinite ||
          !band.gainDb.isFinite ||
          !band.q.isFinite ||
          band.frequencyHz < plan.safetyBounds.minimumFrequencyHz ||
          band.frequencyHz > plan.safetyBounds.maximumFrequencyHz ||
          // Boost is allowed up to `maximumBoostDb` (0 by default = cut-only,
          // >0 for the full-range/broadband profile) — this integrity check
          // must match the same bounds `_bandRejection` and TuneSafetyValidator
          // already enforce, or a legitimately-generated boost band (broadband
          // tonal fill, preference lift) would make generate() throw and fail
          // Tune creation entirely.
          band.gainDb > plan.safetyBounds.maximumBoostDb ||
          band.gainDb < -plan.safetyBounds.maximumCutDb ||
          band.q < plan.safetyBounds.minimumQ ||
          band.q > plan.safetyBounds.maximumQ ||
          !band.safetyValidated) {
        throw const FormatException(
            'A TunePlan band is outside safety bounds.');
      }
      // Only CUTS accrue against the aggregate-cut budget — a boost does not
      // hollow out the overall level, and counting it here would falsely trip
      // the limit (same rule as TuneSafetyValidator).
      if (band.gainDb < 0) aggregate += band.gainDb.abs();
    }
    if (aggregate > plan.safetyBounds.aggregateCutLimitDb) {
      throw const FormatException('The TunePlan aggregate cut is unsafe.');
    }
  }
}

class TunePlanStore {
  static const _key = 'tunai_current_tune_plan_v1';

  static Future<void> save(TunePlan plan) async {
    TunePlanner.validatePlan(plan);
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(_key, jsonEncode(plan.toJson()));
    if (!saved) throw StateError('The TunePlan could not be saved.');
  }

  static Future<TunePlan?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return TunePlan.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      await prefs.remove(_key);
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'audio_analyzer.dart';
import 'room_measurement.dart';

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
  });

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
      );
}

class TuneCorrectionBand {
  final double frequencyHz;
  final double gainDb;
  final double q;
  final String evidenceReference;
  final bool safetyValidated;

  const TuneCorrectionBand({
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    required this.evidenceReference,
    required this.safetyValidated,
  });

  Map<String, dynamic> toJson() => {
        'frequencyHz': frequencyHz,
        'gainDb': gainDb,
        'q': q,
        'evidenceReference': evidenceReference,
        'safetyValidated': safetyValidated,
      };

  factory TuneCorrectionBand.fromJson(Map<String, dynamic> json) =>
      TuneCorrectionBand(
        frequencyHz: (json['frequencyHz'] as num).toDouble(),
        gainDb: (json['gainDb'] as num).toDouble(),
        q: (json['q'] as num).toDouble(),
        evidenceReference: json['evidenceReference'] as String,
        safetyValidated: json['safetyValidated'] as bool,
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
    this.bounds = const TuneSafetyBounds(),
    required this.now,
  });

  TunePlan generate(RoomMeasurement measurement) {
    _validateMeasurement(measurement);
    final rejected = <RejectedTuneCandidate>[];
    final candidates = [...measurement.peaks]..sort((left, right) {
        final byDepth = left.gain.compareTo(right.gain);
        return byDepth != 0
            ? byDepth
            : left.frequency.compareTo(right.frequency);
      });
    final accepted = <TuneCorrectionBand>[];
    var aggregateCut = 0.0;

    for (final peak in candidates) {
      final reason = _candidateRejection(peak, accepted, aggregateCut);
      if (reason != null) {
        rejected.add(RejectedTuneCandidate(
          frequencyHz: peak.frequency.isFinite ? peak.frequency : null,
          reason: reason,
        ));
        continue;
      }
      final cut = math.min(peak.gain.abs(), bounds.maximumCutDb);
      if (aggregateCut + cut > bounds.aggregateCutLimitDb) {
        rejected.add(RejectedTuneCandidate(
          frequencyHz: peak.frequency,
          reason: 'aggregate_cut_limit',
        ));
        continue;
      }
      accepted.add(TuneCorrectionBand(
        frequencyHz: peak.frequency,
        gainDb: -cut,
        q: peak.q.clamp(bounds.minimumQ, bounds.maximumQ).toDouble(),
        evidenceReference:
            '${measurement.id}:peak:${peak.frequency.toStringAsFixed(3)}',
        safetyValidated: true,
      ));
      aggregateCut += cut;
    }

    accepted
        .sort((left, right) => left.frequencyHz.compareTo(right.frequencyHz));
    final plan = TunePlan(
      id: '${measurement.id}:$tunePlanAlgorithmVersion',
      sourceMeasurementId: measurement.id,
      createdAt: now().toUtc(),
      bands: List.unmodifiable(accepted),
      rejectedCandidates: List.unmodifiable(rejected),
      safetyBounds: bounds,
      measurementQuality: measurement.quality,
      measurementConsistency: measurement.consistencyMetric,
      warnings: List.unmodifiable(measurement.warnings),
    );
    validatePlan(plan);
    return plan;
  }

  void _validateMeasurement(RoomMeasurement measurement) {
    if (measurement.schemaVersion != roomMeasurementSchemaVersion ||
        measurement.algorithmVersion != roomMeasurementAlgorithmVersion) {
      throw const FormatException('Unsupported measurement version.');
    }
    if (!measurement.isValid ||
        measurement.quality != CaptureQualityStatus.valid) {
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
    if (peak.q < bounds.minimumQ || peak.q > bounds.maximumQ) {
      return 'q_out_of_bounds';
    }
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
          band.gainDb >= 0 ||
          band.gainDb < -plan.safetyBounds.maximumCutDb ||
          band.q < plan.safetyBounds.minimumQ ||
          band.q > plan.safetyBounds.maximumQ ||
          !band.safetyValidated) {
        throw const FormatException(
            'A TunePlan band is outside safety bounds.');
      }
      aggregate += band.gainDb.abs();
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

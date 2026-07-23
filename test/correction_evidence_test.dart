import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/audio_analyzer.dart' show FrequencyBin, ResonancePeak;
import 'package:tunai/core/correction_evidence.dart';
import 'package:tunai/core/correction_plan.dart';
import 'package:tunai/core/correction_planner.dart';
import 'package:tunai/core/factory_sound_profile.dart';
import 'package:tunai/core/personal_optimization_context.dart';
import 'package:tunai/core/room_measurement.dart';

RoomMeasurement _measurement(
    {List<ResonancePeak>? peaks, double consistency = 1}) {
  final start = DateTime.utc(2026, 7, 17);
  return RoomMeasurement(
    schemaVersion: roomMeasurementSchemaVersion,
    id: 'm',
    roomType: 'Living Room',
    microphoneProfileId: 'Generic Phone Mic',
    hasMicrophoneCalibration: false,
    capturedAt: start,
    timing: CaptureTiming(
      requestedSampleRate: 44100,
      actualSampleRate: 44100,
      channelCount: 1,
      expectedDuration: const Duration(seconds: 10),
      capturedDuration: const Duration(seconds: 10),
      sampleCount: 441000,
      fileSizeBytes: 882044,
      recordingStartedAt: start,
      playbackStartedAt: start,
      playbackCompletedAt: start.add(const Duration(seconds: 10)),
      recordingStoppedAt: start.add(const Duration(seconds: 10)),
    ),
    usableRangeMinHz: 20,
    usableRangeMaxHz: 500,
    frequencyBins: const [
      FrequencyBin(frequency: 20, magnitude: -30),
      FrequencyBin(frequency: 80, magnitude: -17),
      FrequencyBin(frequency: 500, magnitude: -28),
    ],
    peaks: peaks ??
        const [ResonancePeak(frequency: 70, gain: -8, q: 4)],
    consistencyMetric: consistency,
    levels: const CaptureLevelMetrics(
      rms: 0.08,
      peakAbsolute: 0.3,
      estimatedNoiseFloorDbfs: null,
      clippingRatio: 0,
      signalPresent: true,
      severelyClipped: false,
    ),
    quality: CaptureQualityStatus.valid,
    warnings: const [],
  );
}

void main() {
  const planner = CorrectionPlanner();

  CorrectionEvidence evidenceFor(double consistency, {List<ResonancePeak>? peaks}) {
    final m = _measurement(consistency: consistency, peaks: peaks);
    final ctx =
        planner.buildContext(measurement: m, factory: FactorySoundProfile.tunaiOne);
    final plan = planner.planFromContext(measurement: m, context: ctx);
    return CorrectionEvidence.from(context: ctx, plan: plan);
  }

  group('CorrectionEvidence — structured, traceable judgment record', () {
    test('same input → identical evidence (deterministic)', () {
      final a = evidenceFor(0.9);
      final b = evidenceFor(0.9);
      expect(a.toJson(), b.toJson());
    });

    test('records the factory reference being preserved', () {
      final e = evidenceFor(0.9);
      expect(e.factoryReference, 'natural_balanced');
    });

    test('LOW confidence records the protective strategy + reason', () {
      final e = evidenceFor(0.2);
      expect(e.measurementConfidence, 'low');
      expect(e.strategy, CorrectionStrategy.lowConfidenceIgnore);
      expect(e.reason, 'measurement_low_confidence_preserved_factory');
    });

    test('a balanced room records the factory-preservation decision', () {
      final e = evidenceFor(0.9, peaks: const []);
      expect(e.roomCondition, 'balanced');
      expect(e.strategy, CorrectionStrategy.preserveFactoryCharacter);
      expect(e.reason, 'room_balanced_preserved_factory');
    });

    test('a trustworthy room excess records the corrective decision', () {
      final e = evidenceFor(0.9);
      expect(e.roomCondition, 'bassBoom');
      expect(e.strategy, CorrectionStrategy.reduceRoomExcess);
      expect(e.reason, 'reduced_room_excess');
    });

    test('carries NO DSP value in any field or its serialized form', () {
      final serialized = evidenceFor(0.2).toJson().toString().toLowerCase();
      for (final forbidden in [
        'frequency', 'hz', 'gain', 'db', 'q:', 'filter', 'peq', 'crossover',
        'delay', 'limiter', 'register', 'biquad',
      ]) {
        expect(serialized.contains(forbidden), isFalse,
            reason: 'evidence must not carry "$forbidden": $serialized');
      }
    });

    test('round-trips through JSON', () {
      final e = evidenceFor(0.2);
      final back = CorrectionEvidence.fromJson(e.toJson());
      expect(back.factoryReference, e.factoryReference);
      expect(back.roomCondition, e.roomCondition);
      expect(back.measurementConfidence, e.measurementConfidence);
      expect(back.strategy, e.strategy);
      expect(back.reason, e.reason);
    });

    test('every strategy maps to a distinct, stable reason code', () {
      final reasons = <String>{};
      for (final s in CorrectionStrategy.values) {
        final evidence = CorrectionEvidence.from(
          context: const PersonalOptimizationContext(roomCondition: 'bassBoom'),
          plan: CorrectionPlan(
            problem: AcousticProblem.bassBoom,
            goal: CorrectionGoal.tighterLowEnd,
            strategy: s,
          ),
        );
        reasons.add(evidence.reason);
      }
      expect(reasons.length, CorrectionStrategy.values.length,
          reason: 'each strategy should have its own reason code');
    });
  });
}

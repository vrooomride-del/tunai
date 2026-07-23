import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/audio_analyzer.dart' show FrequencyBin, ResonancePeak;
import 'package:tunai/core/acoustic_intent.dart';
import 'package:tunai/core/correction_plan.dart';
import 'package:tunai/core/correction_planner.dart';
import 'package:tunai/core/factory_sound_profile.dart';
import 'package:tunai/core/listening_taste.dart';
import 'package:tunai/core/room_measurement.dart';
import 'package:tunai/core/sound_preference.dart';
import 'package:tunai/core/tune_plan.dart';

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
        const [
          ResonancePeak(frequency: 80, gain: -5, q: 4),
          ResonancePeak(frequency: 220, gain: -3, q: 3),
        ],
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

  group('CorrectionPlanner.plan — measurement + intent → CorrectionPlan (7.1)',
      () {
    test('produces a valid perceptual plan from measurement alone', () {
      final plan = planner.plan(measurement: _measurement());
      expect(plan.problem, isA<AcousticProblem>());
      expect(plan.goal, isA<CorrectionGoal>());
      expect(plan.allowed, isTrue);
      // No intent → measurement-led priority, no preference override.
      expect(plan.priority, CorrectionPriority.measurement);
      expect(plan.preferenceContext, isNull);
    });

    test('a dominant low-frequency issue reads as bass_boom / tighter low end',
        () {
      final plan = planner.plan(
        measurement: _measurement(
            peaks: const [ResonancePeak(frequency: 70, gain: -8, q: 4)]),
      );
      expect(plan.problem, AcousticProblem.bassBoom);
      expect(plan.goal, CorrectionGoal.tighterLowEnd);
    });

    test('warm + long-listening intent flows into perceptual context', () {
      final plan = planner.plan(
        measurement: _measurement(),
        intent: const AcousticIntent(
          soundCharacter: SoundCharacter.warm,
          listeningGoal: ListeningGoal.longListening,
          confidence: IntentConfidence.high,
        ),
      );
      expect(plan.intentContext['soundCharacter'], 'warm');
      expect(plan.intentContext['listeningGoal'], 'longListening');
      expect(plan.priority, CorrectionPriority.userPreference);
      expect(plan.preferenceContext, 'warm');
    });

    test('factory sound intent is carried as perceptual context (Phase 3-2)',
        () {
      final plan = planner.plan(
        measurement: _measurement(),
        factory: FactorySoundProfile.tunaiOne,
      );
      expect(plan.intentContext['factoryTarget'], 'natural_balanced');
      expect(plan.intentContext['factoryIntent'], 'accurate_long_listening');
      expect(plan.intentContext['factoryListeningGoal'], 'comfortable_detail');
      expect(plan.intentContext['safeOperatingRange'], 'moderate');
    });

    test('the documented example: factory natural + room bass_boom + user warm',
        () {
      // Factory=natural, Room=bass boom, User=warm → the plan names the bass
      // problem, keeps the factory intent as context, and carries the user's
      // warm direction — all perceptual.
      final plan = planner.plan(
        measurement: _measurement(
            peaks: const [ResonancePeak(frequency: 70, gain: -8, q: 4)]),
        intent: const AcousticIntent(
            soundCharacter: SoundCharacter.warm,
            confidence: IntentConfidence.high),
        factory: FactorySoundProfile.tunaiOne,
      );
      expect(plan.problem, AcousticProblem.bassBoom);
      expect(plan.intentContext['factoryTarget'], 'natural_balanced');
      expect(plan.intentContext['soundCharacter'], 'warm');
      expect(plan.preferenceContext, 'warm');
    });
  });

  group('PersonalOptimizationContext + strategy (Phase 3-3)', () {
    test('a room bass boom → reduceRoomExcess, factory preserved', () {
      final plan = planner.plan(
        measurement: _measurement(
            peaks: const [ResonancePeak(frequency: 70, gain: -8, q: 4)]),
        factory: FactorySoundProfile.tunaiOne,
      );
      expect(plan.problem, AcousticProblem.bassBoom);
      expect(plan.strategy, CorrectionStrategy.reduceRoomExcess);
      // Factory character carried as context to preserve, not corrected toward.
      expect(plan.intentContext['factoryTarget'], 'natural_balanced');
    });

    test('a room dip (positive gain) → fillRoomDip', () {
      final plan = planner.plan(
        measurement: _measurement(
            peaks: const [ResonancePeak(frequency: 90, gain: 3, q: 4)]),
      );
      expect(plan.strategy, CorrectionStrategy.fillRoomDip);
    });

    test('no measured problem → preserveFactoryCharacter (do not invent a fix)',
        () {
      final plan = planner.plan(measurement: _measurement(peaks: const []));
      expect(plan.strategy, CorrectionStrategy.preserveFactoryCharacter);
    });

    test('buildContext keeps the four inputs separate and perceptual', () {
      final ctx = planner.buildContext(
        measurement: _measurement(
            peaks: const [ResonancePeak(frequency: 70, gain: -8, q: 4)]),
        intent: const AcousticIntent(
            soundCharacter: SoundCharacter.warm,
            listeningGoal: ListeningGoal.longListening,
            confidence: IntentConfidence.high),
        taste: ListeningTaste.warm,
        factory: FactorySoundProfile.tunaiOne,
      );
      expect(ctx.factoryReference?.speakerModel, 'TUNAI ONE');
      expect(ctx.roomCondition, 'bassBoom');
      expect(ctx.userPreference, 'warm');
      expect(ctx.listeningIntent['listeningGoal'], 'longListening');
      expect(ctx.hasUserSignal, isTrue);
      // No number anywhere in the serialized context.
      final serialized = ctx.toJson().toString().toLowerCase();
      for (final forbidden in [
        'frequency', 'hz', 'gain', 'db', 'q:', 'crossover', 'delay',
        'limiter', 'register',
      ]) {
        expect(serialized.contains(forbidden), isFalse);
      }
    });

    test('an intent-free context reduces to "preserve factory, correct room"',
        () {
      final ctx = planner.buildContext(
        measurement: _measurement(),
        factory: FactorySoundProfile.tunaiOne,
      );
      expect(ctx.hasUserSignal, isFalse);
      expect(ctx.userPreference, isNull);
      expect(ctx.listeningIntent, isEmpty);
    });
  });

  group('FactoryProfile connection is behaviour-preserving (Phase 3-2)', () {
    test('passing a factory profile does NOT change which preference resolves',
        () {
      final measurement = _measurement();
      final withoutFactory = planner.plan(measurement: measurement);
      final withFactory = planner.plan(
          measurement: measurement, factory: FactorySoundProfile.tunaiOne);
      // Factory adds context but must never override the picker fallback.
      for (final fb in SoundPreference.values) {
        expect(planner.resolvePreference(withFactory, fallback: fb),
            planner.resolvePreference(withoutFactory, fallback: fb));
        expect(planner.resolvePreference(withFactory, fallback: fb), fb);
      }
    });

    test('factory-derived context contains no numeric field', () {
      final plan = planner.plan(
          measurement: _measurement(), factory: FactorySoundProfile.tunaiOne);
      final serialized = plan.toJson().toString().toLowerCase();
      for (final forbidden in [
        'frequency', 'hz', 'gain', 'db', 'q:', 'crossover', 'delay',
        'limiter', 'register',
      ]) {
        expect(serialized.contains(forbidden), isFalse);
      }
    });
  });

  group('CorrectionPlan carries NO DSP values (7.2)', () {
    test('the plan and its serialized form expose no numeric tuning field', () {
      final plan = planner.plan(
        measurement: _measurement(),
        intent: const AcousticIntent(
          soundCharacter: SoundCharacter.warm,
          confidence: IntentConfidence.high,
        ),
        taste: ListeningTaste.warm,
        factory: FactorySoundProfile.tunaiOne,
      );
      final serialized = plan.toJson().toString().toLowerCase();
      for (final forbidden in [
        'frequency', 'hz', 'gain', 'db', 'q:', 'filter', 'peq', 'crossover',
        'delay', 'limiter', 'register', 'biquad',
      ]) {
        expect(serialized.contains(forbidden), isFalse,
            reason: 'CorrectionPlan must not carry "$forbidden": $serialized');
      }
    });
  });

  group('resolvePreference — the TunePlanner connection', () {
    test('no override → returns the picker fallback UNCHANGED (7.4 behaviour '
        'preservation)', () {
      final plan = planner.plan(measurement: _measurement());
      for (final fallback in SoundPreference.values) {
        expect(planner.resolvePreference(plan, fallback: fallback), fallback,
            reason: 'intent-free flow must be identical to before Phase 3');
      }
    });

    test('warm intent resolves to the existing warm preference', () {
      final plan = planner.plan(
        measurement: _measurement(),
        intent: const AcousticIntent(
            soundCharacter: SoundCharacter.warm,
            confidence: IntentConfidence.high),
      );
      expect(planner.resolvePreference(plan, fallback: SoundPreference.balanced),
          SoundPreference.warm);
    });

    test('detailed → clear, relaxed → open, natural → balanced', () {
      SoundPreference resolve(SoundCharacter c) => planner.resolvePreference(
            planner.plan(
                measurement: _measurement(),
                intent: AcousticIntent(
                    soundCharacter: c, confidence: IntentConfidence.high)),
            fallback: SoundPreference.vocal,
          );
      expect(resolve(SoundCharacter.detailed), SoundPreference.clear);
      expect(resolve(SoundCharacter.relaxed), SoundPreference.open);
      expect(resolve(SoundCharacter.natural), SoundPreference.balanced);
    });

    test('energetic and deepBass stay context-only — they fall back rather '
        'than inventing new EQ math', () {
      final energetic = planner.plan(
        measurement: _measurement(),
        intent: const AcousticIntent(
            soundCharacter: SoundCharacter.energetic,
            confidence: IntentConfidence.high),
      );
      expect(
          planner.resolvePreference(energetic, fallback: SoundPreference.vocal),
          SoundPreference.vocal);

      final deepBass =
          planner.plan(measurement: _measurement(), taste: ListeningTaste.deepBass);
      expect(deepBass.preferenceContext, isNull);
      expect(
          planner.resolvePreference(deepBass, fallback: SoundPreference.balanced),
          SoundPreference.balanced);
    });

    test('intent outranks a stored taste when both are present', () {
      final plan = planner.plan(
        measurement: _measurement(),
        intent: const AcousticIntent(
            soundCharacter: SoundCharacter.detailed,
            confidence: IntentConfidence.high),
        taste: ListeningTaste.warm,
      );
      expect(plan.preferenceContext, 'detailed');
    });
  });

  group('TunePlanner regression — same output with a null-override plan (7.3)',
      () {
    test('resolvePreference(no override) yields the SAME TunePlan as calling '
        'TunePlanner with the picker preference directly', () {
      final measurement = _measurement();
      final plan = planner.plan(measurement: measurement);
      final resolved =
          planner.resolvePreference(plan, fallback: SoundPreference.balanced);

      final viaContext =
          TunePlanner(now: () => DateTime.utc(2026)).generate(measurement,
              preference: resolved);
      final direct = TunePlanner(now: () => DateTime.utc(2026))
          .generate(measurement, preference: SoundPreference.balanced);

      expect(viaContext.id, direct.id);
      expect(viaContext.bands.map((b) => b.toJson()),
          direct.bands.map((b) => b.toJson()));
    });
  });

  group('planFromContext — context-driven flow (Phase 3-4)', () {
    const planner = CorrectionPlanner();

    test('produces the same tuning direction as plan() for the same inputs',
        () {
      final measurement = _measurement(
          peaks: const [ResonancePeak(frequency: 70, gain: -8, q: 4)]);
      final context = planner.buildContext(
          measurement: measurement, factory: FactorySoundProfile.tunaiOne);
      final fromContext =
          planner.planFromContext(measurement: measurement, context: context);
      final direct = planner.plan(
          measurement: measurement, factory: FactorySoundProfile.tunaiOne);

      expect(fromContext.problem, direct.problem);
      expect(fromContext.strategy, direct.strategy);
      // No user signal → both resolve to the picker fallback unchanged.
      for (final fb in SoundPreference.values) {
        expect(planner.resolvePreference(fromContext, fallback: fb),
            planner.resolvePreference(direct, fallback: fb));
        expect(planner.resolvePreference(fromContext, fallback: fb), fb);
      }
    });

    test('carries the factory intent and (when present) the user preference',
        () {
      final measurement = _measurement();
      final context = planner.buildContext(
        measurement: measurement,
        taste: ListeningTaste.warm,
        factory: FactorySoundProfile.tunaiOne,
      );
      final plan =
          planner.planFromContext(measurement: measurement, context: context);
      expect(plan.intentContext['factoryTarget'], 'natural_balanced');
      expect(plan.preferenceContext, 'warm');
      expect(plan.intentContext['preference'], 'warm');
    });

    test('the context-driven plan carries no numeric field', () {
      final measurement = _measurement(
          peaks: const [ResonancePeak(frequency: 70, gain: -8, q: 4)]);
      final context = planner.buildContext(
          measurement: measurement, factory: FactorySoundProfile.tunaiOne);
      final plan =
          planner.planFromContext(measurement: measurement, context: context);
      final serialized = plan.toJson().toString().toLowerCase();
      for (final forbidden in [
        'frequency', 'hz', 'gain', 'db', 'q:', 'crossover', 'delay',
        'limiter', 'register',
      ]) {
        expect(serialized.contains(forbidden), isFalse);
      }
    });
  });


  group('Runtime intent reflection (Phase 3-6)', () {
    const planner = CorrectionPlanner();

    test('a stored WARM intent flows through the existing preference channel',
        () {
      final measurement = _measurement();
      final context = planner.buildContext(
        measurement: measurement,
        intent: const AcousticIntent(
            soundCharacter: SoundCharacter.warm,
            confidence: IntentConfidence.high),
        factory: FactorySoundProfile.tunaiOne,
      );
      final plan =
          planner.planFromContext(measurement: measurement, context: context);
      // Reflected: maps to the real, existing warm SoundPreference.
      expect(
          planner.resolvePreference(plan, fallback: SoundPreference.balanced),
          SoundPreference.warm);
    });

    test('a DeepBass-style intent stays context-only, never force-mapped to DSP',
        () {
      final measurement = _measurement();
      // No soundCharacter maps deepBass; a bass "powerful" intent has no safe
      // existing SoundPreference, so it must NOT change the resolved preference.
      final context = planner.buildContext(
        measurement: measurement,
        intent: const AcousticIntent(
            bassPreference: BassPreference.powerful,
            confidence: IntentConfidence.high),
        factory: FactorySoundProfile.tunaiOne,
      );
      final plan =
          planner.planFromContext(measurement: measurement, context: context);
      for (final fb in SoundPreference.values) {
        expect(planner.resolvePreference(plan, fallback: fb), fb,
            reason: 'unsupported intent must not override the picker');
      }
    });

    test('no stored intent → identical resolved preference (band-level parity '
        'guaranteed by the TunePlanner regression above)', () {
      final measurement = _measurement();
      final context = planner.buildContext(
          measurement: measurement, factory: FactorySoundProfile.tunaiOne);
      final plan =
          planner.planFromContext(measurement: measurement, context: context);
      for (final fb in SoundPreference.values) {
        expect(planner.resolvePreference(plan, fallback: fb), fb);
      }
    });
  });


  group('Phase 4 — CorrectionPlanner as a judgment layer', () {
    const planner = CorrectionPlanner();

    CorrectionPlan planWith({
      required double consistency,
      AcousticIntent? intent,
      List<ResonancePeak>? peaks,
    }) {
      final m = _measurement(consistency: consistency, peaks: peaks);
      final ctx = planner.buildContext(
          measurement: m, intent: intent, factory: FactorySoundProfile.tunaiOne);
      return planner.planFromContext(measurement: m, context: ctx);
    }

    test('confidence is a REAL measured value carried into context', () {
      final ctx = planner.buildContext(
          measurement: _measurement(consistency: 0.3),
          factory: FactorySoundProfile.tunaiOne);
      expect(ctx.confidence, 'low');
      expect(ctx.measurementQuality, 'valid');
    });

    test('high confidence + room excess → correct, and preference is applied',
        () {
      final plan = planWith(
        consistency: 0.9,
        peaks: const [ResonancePeak(frequency: 70, gain: -8, q: 4)],
        intent: const AcousticIntent(
            soundCharacter: SoundCharacter.warm,
            confidence: IntentConfidence.high),
      );
      expect(plan.strategy, CorrectionStrategy.reduceRoomExcess);
      expect(planner.resolvePreference(plan, fallback: SoundPreference.balanced),
          SoundPreference.warm);
    });

    test('LOW confidence → lowConfidenceIgnore, preference NOT applied', () {
      final plan = planWith(
        consistency: 0.2,
        peaks: const [ResonancePeak(frequency: 70, gain: -8, q: 4)],
        intent: const AcousticIntent(
            soundCharacter: SoundCharacter.warm,
            confidence: IntentConfidence.high),
      );
      expect(plan.strategy, CorrectionStrategy.lowConfidenceIgnore);
      // The user's warm preference is held back — factory sound protected.
      for (final fb in SoundPreference.values) {
        expect(planner.resolvePreference(plan, fallback: fb), fb);
      }
    });

    test('MODERATE confidence + preference → protectFactoryCharacter, preference '
        'stays secondary', () {
      final plan = planWith(
        consistency: 0.6,
        peaks: const [ResonancePeak(frequency: 70, gain: -8, q: 4)],
        intent: const AcousticIntent(
            soundCharacter: SoundCharacter.warm,
            confidence: IntentConfidence.high),
      );
      expect(plan.strategy, CorrectionStrategy.protectFactoryCharacter);
      expect(planner.resolvePreference(plan, fallback: SoundPreference.balanced),
          SoundPreference.balanced);
    });

    test('factory-natural balanced room stays preserved regardless of confidence',
        () {
      final plan = planWith(consistency: 0.9, peaks: const []);
      expect(plan.strategy, CorrectionStrategy.preserveFactoryCharacter);
    });

    test('user preference NEVER destroys factory: low confidence holds the '
        'factory sound even with a strong request', () {
      final plan = planWith(
        consistency: 0.2,
        intent: const AcousticIntent(
            soundCharacter: SoundCharacter.detailed,
            confidence: IntentConfidence.high),
      );
      expect(plan.preferenceContext, isNull);
      expect(planner.resolvePreference(plan, fallback: SoundPreference.balanced),
          SoundPreference.balanced);
    });

    test('no user input → identical resolved preference at EVERY confidence '
        '(regression: judgment never changes the intent-free flow)', () {
      for (final c in [0.2, 0.6, 0.9]) {
        final plan = planWith(consistency: c);
        for (final fb in SoundPreference.values) {
          expect(planner.resolvePreference(plan, fallback: fb), fb,
              reason: 'consistency=$c must not change the no-input result');
        }
      }
    });

    test('the judgment plan still carries no numeric field', () {
      final plan = planWith(
        consistency: 0.2,
        peaks: const [ResonancePeak(frequency: 70, gain: -8, q: 4)],
        intent: const AcousticIntent(
            soundCharacter: SoundCharacter.warm,
            confidence: IntentConfidence.high),
      );
      final serialized = plan.toJson().toString().toLowerCase();
      for (final forbidden in [
        'frequency', 'hz', 'gain', 'db', 'q:', 'crossover', 'delay',
        'limiter', 'register',
      ]) {
        expect(serialized.contains(forbidden), isFalse);
      }
    });
  });

}
